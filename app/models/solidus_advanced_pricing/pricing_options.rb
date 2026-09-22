# frozen_string_literal: true

module SolidusAdvancedPricing
  # desired_attributes describes the price being sought and may hold only assignable
  # Spree::Price columns, because core calls prices.build(default_price_attributes).
  # at/customer_role_ids describe who is asking and live outside that hash.
  class PricingOptions < ::Spree::Variant::PricingOptions
    attr_reader :at, :customer_role_ids

    def self.default_price_attributes
      super.merge(
        price_type_id: nil,
        role_id: nil
      )
    end

    # price_type_id: :any means "no type filter, every type competes". nil, the
    # default set by default_price_attributes above, means "untyped base prices
    # only" and must not leak into a customer-facing lookup, or a sale price
    # could never be selected.
    def self.from_line_item(line_item)
      options = super
      new(
        options.desired_attributes.merge(
          price_type_id: :any,
          customer_role_ids: pricing_relevant_role_ids(line_item.order&.user)
        )
      )
    end

    # price_type_id: :any (see from_line_item above).
    def self.from_context(context)
      options = super
      new(
        options.desired_attributes.merge(
          price_type_id: :any,
          customer_role_ids: pricing_relevant_role_ids(context.try(:current_spree_user))
        )
      )
    end

    def self.from_price(price)
      new(
        currency: price.currency,
        country_iso: price.country_iso,
        price_type_id: price.price_type_id,
        role_id: price.role_id
      )
    end

    # Narrowed to roles some price actually uses: selection is unaffected, but it
    # collapses cache key cardinality (Task 12).
    def self.pricing_relevant_role_ids(user)
      return [] if user.nil?

      user.spree_role_ids & SolidusAdvancedPricing::PriceTypeCache.pricing_role_ids
    end

    def initialize(desired_attributes = {})
      attributes = desired_attributes.dup
      @at = attributes.key?(:at) ? attributes.delete(:at) : Time.current
      @customer_role_ids = Array(attributes.delete(:customer_role_ids))
      super(attributes)
    end

    # Core keys only on desired_attributes; customer context lives outside it, so
    # without this a role-targeted price would be cached and served to a guest.
    def cache_key
      [super, roles_cache_component, time_cache_component].compact.join("/")
    end

    # nil is a real filter now (price_type_id IS NULL matches untyped base prices)
    # and is kept; :any means no type filter at all, so it's stripped instead —
    # it's a selector-only sentinel and not a column value `where` could use.
    def search_arguments
      arguments = desired_attributes.dup
      arguments[:country_iso] = [desired_attributes[:country_iso], nil].flatten.uniq
      arguments[:role_id] = [nil, *customer_role_ids].uniq
      arguments.delete(:price_type_id) if desired_attributes[:price_type_id] == :any
      arguments
    end

    private

    def roles_cache_component
      return "r-none" if customer_role_ids.empty?

      "r-#{customer_role_ids.sort.join("-")}"
    end

    def time_cache_component
      granularity = ::Spree::Config.advanced_pricing_cache_granularity.to_i
      return nil if granularity <= 0
      return nil if at.nil?

      "t-#{at.to_i / granularity}"
    end
  end
end
