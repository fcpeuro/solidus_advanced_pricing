# frozen_string_literal: true

module SolidusAdvancedPricing
  # desired_attributes describes the price being sought and may hold only assignable
  # Spree::Price columns, because core calls prices.build(default_price_attributes).
  # at/customer_role_ids describe who is asking and live outside that hash.
  class PricingOptions < ::Spree::Variant::PricingOptions
    attr_reader :at, :customer_role_ids

    def self.default_price_attributes
      super.merge(
        price_type_id: SolidusAdvancedPricing::PriceTypeCache.default_id,
        role_id: nil
      )
    end

    # price_type_id: nil means "any type competes". default_price_attributes pins it
    # to the default type so the admin edits the base price; customers must not inherit
    # that pin or a sale price could never be selected.
    def self.from_line_item(line_item)
      options = super
      new(
        options.desired_attributes.merge(
          price_type_id: nil,
          customer_role_ids: pricing_relevant_role_ids(line_item.order&.user)
        )
      )
    end

    # price_type_id: nil means "any type competes" (see from_line_item above).
    def self.from_context(context)
      options = super
      new(
        options.desired_attributes.merge(
          price_type_id: nil,
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
  end
end
