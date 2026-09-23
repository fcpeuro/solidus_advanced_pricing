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

    # Everything a natural-key row may change. Anything in the key is, by
    # definition, how the row was found, so changing it there is incoherent.
    UPDATABLE = %i[amount valid_to admin_notes].freeze

    # An `id` names the row outright, so nothing is off-limits except which
    # variant it hangs off. `price_type_id` is listed but the model refuses to
    # change it on a persisted price, which surfaces as an ordinary row error.
    UPDATABLE_BY_ID = %i[amount currency country_iso price_type_id role_id valid_from valid_to admin_notes].freeze

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
    # Two ways to name a row, and `id` wins when it is there: it says exactly
    # which price to change, with no key to assemble and no precision to lose.
    #
    # The natural key is what a payload authored somewhere that does not know
    # Solidus ids -- a supplier feed, a merchandiser's spreadsheet, a backfill
    # from another system -- has instead. It is also what makes such a payload
    # re-runnable: without it, a nightly feed has no ids on its rows and would
    # create a fresh duplicate of every price on every pass.
    def apply_row(row, index, seen)
      located = row[:id].present? ? locate_by_id(row) : locate_by_key(row)
      return record(index, :error, errors: [located]) if located.is_a?(String)

      price, variant_id, price_type_id, dedup, attributes = located

      if seen.key?(dedup)
        return record(index, :error, variant_id: variant_id,
          errors: ["duplicate of row #{seen[dedup]}: #{duplicate_reason(dedup)}"])
      end
      seen[dedup] = index

      persist(index, price, variant_id, price_type_id, attributes)
    end

    def duplicate_reason(dedup)
      if dedup.first == :id
        "same price id"
      else
        "same variant, currency, country, price type, role and valid_from"
      end
    end

    def locate_by_id(row)
      price = ::Spree::Price.kept.find_by(id: row[:id])
      return "no price with id #{row[:id]}" if price.nil?

      variant = resolve_variant(row) unless row[:variant_id].blank? && row[:sku].blank?
      return "variant: #{variant}" if variant.is_a?(String)
      if variant && variant.id != price.variant_id
        return "price #{price.id} belongs to variant #{price.variant_id}, not #{variant.id}"
      end

      price_type_id = resolve_price_type_id(row)
      return "price_type: #{price_type_id}" if price_type_id.is_a?(String)

      attributes = row.slice(*UPDATABLE_BY_ID)
      attributes[:price_type_id] = price_type_id if row.key?(:price_type_code)

      [price, price.variant_id, price.price_type_id, [:id, price.id], attributes]
    end

    def locate_by_key(row)
      variant = resolve_variant(row)
      return "variant: #{variant}" if variant.is_a?(String)

      price_type_id = resolve_price_type_id(row)
      return "price_type: #{price_type_id}" if price_type_id.is_a?(String)

      key = natural_key(row, variant, price_type_id)
      price = find_existing(key) || ::Spree::Price.new(key)

      [price, variant.id, price_type_id, [:key, key], row.slice(*UPDATABLE)]
    end

    # Each row gets its own savepoint: one bad row must not poison the batch,
    # and on PostgreSQL a raised constraint error would otherwise abort every
    # statement that follows it in the transaction.
    def persist(index, price, variant_id, price_type_id, attributes)
      ActiveRecord::Base.transaction(requires_new: true) do
        existing = price.persisted?
        price.assign_attributes(attributes)

        if existing && !price.changed?
          touch(variant_id, price_type_id, price.id)
          record(index, :unchanged, price_id: price.id, variant_id: variant_id)
        elsif price.save
          touch(variant_id, price.price_type_id, price.id)
          record(index, existing ? :updated : :created, price_id: reportable_id(price), variant_id: variant_id)
        else
          # Recorded before the rollback on purpose: @results is a Ruby array,
          # so the savepoint unwinding the row does not unwind the report of it.
          record(index, :error, variant_id: variant_id, errors: price.errors.full_messages)
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
