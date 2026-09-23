# frozen_string_literal: true

module SolidusAdvancedPricing
  # Applies many price rows in one call, keyed on the dimensions a price
  # legitimately varies on, so re-sending the same payload is a no-op rather
  # than a pile of duplicates.
  #
  # Deliberately generic: it validates and writes prices and reports what it
  # did. Store policy -- how large a swing is allowed, what gets reindexed,
  # what gets published on an event bus -- belongs to the host app, which can
  # hang it off `SolidusAdvancedPricing.config.batch_guard` or act on the
  # returned results.
  class PriceBatch
    MODES = %w[upsert replace].freeze

    # Two rows agreeing on all of these are the same price. `valid_to` is
    # deliberately absent: extending or shortening a window is an edit to an
    # existing price, not a different one.
    NATURAL_KEY = %i[variant_id currency country_iso price_type_id role_id valid_from].freeze

    # Everything a matched row may change. Anything in the natural key is,
    # by definition, how the row was found.
    UPDATABLE = %i[amount valid_to admin_notes].freeze

    class TooManyRows < StandardError; end

    class InvalidMode < StandardError; end

    Result = Struct.new(:index, :status, :price_id, :variant_id, :errors, keyword_init: true) do
      def to_h
        {index: index, status: status, price_id: price_id, variant_id: variant_id, errors: errors}.compact
      end
    end

    attr_reader :results, :mode

    def initialize(rows:, mode: "upsert", dry_run: false, row_limit: nil)
      @rows = Array(rows)
      @mode = mode.to_s
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run) || false
      @row_limit = row_limit || SolidusAdvancedPricing.config.batch_row_limit
      @results = []
      @touched_ids = Hash.new { |hash, key| hash[key] = [] }

      raise InvalidMode, "mode must be one of #{MODES.join(", ")}" unless MODES.include?(@mode)
      raise TooManyRows, "batch is limited to #{@row_limit} rows, got #{@rows.size}" if @rows.size > @row_limit
    end

    def dry_run? = @dry_run

    def replace? = @mode == "replace"

    def call
      # A dry run does the real work against the database and throws it away, so
      # what it reports is what the write would actually do -- validations, type
      # casting and constraints included -- rather than a guess at it.
      ActiveRecord::Base.transaction do
        seen = {}

        @rows.each_with_index do |row, index|
          apply_row(row.to_h.symbolize_keys, index, seen)
        end

        apply_replacements if replace?

        # The host app's veto, with every row already written and nothing
        # committed. Raising from here aborts the whole batch -- which is the
        # only place a "this moves too many prices too far" rule can see the
        # finished picture and still stop it.
        SolidusAdvancedPricing.config.batch_guard&.call(self)

        raise ActiveRecord::Rollback if dry_run?
      end

      self
    end

    def summary
      results.group_by(&:status).transform_values(&:size)
    end

    private

    # Resolution happens outside the savepoint -- it touches no state, and a
    # `return` out of a transaction block is a trap worth not setting.
    def apply_row(row, index, seen)
      variant = resolve_variant(row)
      return record(index, :error, errors: ["variant: #{variant}"]) if variant.is_a?(String)

      price_type_id = resolve_price_type_id(row)
      if price_type_id.is_a?(String)
        return record(index, :error, variant_id: variant.id, errors: ["price_type: #{price_type_id}"])
      end

      key = natural_key(row, variant, price_type_id)

      if seen.key?(key)
        return record(index, :error, variant_id: variant.id,
          errors: ["duplicate of row #{seen[key]}: same variant, currency, country, price type, role and valid_from"])
      end
      seen[key] = index

      # Each row gets its own savepoint: one bad row must not poison the batch,
      # and on PostgreSQL a raised constraint error would otherwise abort every
      # statement that follows it in the transaction.
      ActiveRecord::Base.transaction(requires_new: true) do
        price = find_existing(key) || ::Spree::Price.new(key)
        existing = price.persisted?

        price.assign_attributes(row.slice(*UPDATABLE))

        if existing && !price.changed?
          touch(variant.id, price_type_id, price.id)
          record(index, :unchanged, price_id: price.id, variant_id: variant.id)
        elsif price.save
          touch(variant.id, price_type_id, price.id)
          record(index, existing ? :updated : :created, price_id: reportable_id(price), variant_id: variant.id)
        else
          # Recorded before the rollback on purpose: @results is a Ruby array,
          # so the savepoint unwinding the row does not unwind the report of it.
          record(index, :error, variant_id: variant.id, errors: price.errors.full_messages)
          raise ActiveRecord::Rollback
        end
      end
    end

    def touch(variant_id, price_type_id, price_id)
      @touched_ids[[variant_id, price_type_id]] << price_id
    end

    # Only prices of a type the payload actually spoke about, on a variant the
    # payload actually named, are in scope. A `replace` that named one sale
    # price must not reach the variant's base price or its wholesale tier.
    def apply_replacements
      @touched_ids.each do |(variant_id, price_type_id), kept_ids|
        stale = ::Spree::Price.kept.where(variant_id: variant_id, price_type_id: price_type_id).where.not(id: kept_ids)

        stale.each do |price|
          price.discard
          @results << Result.new(index: nil, status: :deleted, price_id: price.id, variant_id: variant_id)
        end
      end
    end

    def resolve_variant(row)
      if row[:variant_id].present? && row[:sku].present?
        return "give variant_id or sku, not both"
      end

      if row[:variant_id].present?
        ::Spree::Variant.find_by(id: row[:variant_id]) || "no variant with id #{row[:variant_id]}"
      elsif row[:sku].present?
        ::Spree::Variant.find_by(sku: row[:sku]) || "no variant with sku #{row[:sku].inspect}"
      else
        "variant_id or sku is required"
      end
    end

    # Mirrors the single-price endpoint: a code is portable between databases
    # where an id is not. Returns a String to signal failure, since nil is the
    # legitimate value for the untyped base price.
    def resolve_price_type_id(row)
      has_code = row.key?(:price_type_code)
      return "give price_type_id or price_type_code, not both" if has_code && row[:price_type_id].present?
      return row[:price_type_id].presence && row[:price_type_id].to_i unless has_code

      code = row[:price_type_code]
      return nil if code.blank?

      SolidusAdvancedPricing.resolve_price_type_id(code)
    rescue ArgumentError
      "no price type with code #{code.inspect}"
    end

    def natural_key(row, variant, price_type_id)
      valid_from = ::Spree::Price.type_for_attribute(:valid_from).cast(row[:valid_from].presence)

      {
        variant_id: variant.id,
        currency: row[:currency].presence || ::Spree::Config.default_pricing_options.currency,
        country_iso: row[:country_iso].presence,
        price_type_id: price_type_id,
        role_id: row[:role_id].presence && row[:role_id].to_i,
        # Truncated to the second so the key survives a round trip: a client that
        # read a price back and re-sent its `valid_from` may have dropped the
        # sub-second part, and treating that as a different price would duplicate
        # the row -- and in `replace` mode, discard the original.
        valid_from: valid_from&.change(usec: 0)
      }
    end

    # Matching is a one-second window rather than an equality, so a price that
    # was stored with sub-second precision by some other writer is still found
    # by a truncated key.
    def find_existing(key)
      scope = ::Spree::Price.kept.where(key.except(:valid_from))
      from = key[:valid_from]

      return scope.find_by(valid_from: nil) if from.nil?

      scope.where(valid_from: from...(from + 1.second)).first
    end

    # A dry run rolls back, so any id it allocated is about to stop existing.
    # Reporting it would invite a client to use it.
    def reportable_id(price)
      dry_run? ? nil : price.id
    end

    def record(index, status, price_id: nil, variant_id: nil, errors: nil)
      @results << Result.new(index: index, status: status, price_id: price_id, variant_id: variant_id, errors: errors)
    end
  end
end
