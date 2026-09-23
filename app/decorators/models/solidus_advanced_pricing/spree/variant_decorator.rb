# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module VariantDecorator
      def self.prepended(base)
        base.singleton_class.prepend(ClassMethods)
      end

      module ClassMethods
        # Core checks only currency and country, so an expired or role-targeted
        # price still makes a variant look purchasable in listings.
        def with_prices(pricing_options = ::Spree::Config.default_pricing_options)
          relation = ::Spree::Price
            .where(::Spree::Variant.arel_table[:id].eq(::Spree::Price.arel_table[:variant_id]))
            .where(currency: pricing_options.currency)
            .where(country_iso: [pricing_options.country_iso, nil].uniq)

          relation = relation.valid_at(pricing_options.at) if pricing_options.try(:at)
          if pricing_options.respond_to?(:customer_role_ids)
            relation = relation.visible_to_roles(pricing_options.customer_role_ids)
          end

          where(relation.arel.exists)
        end
      end

      # nil means the untyped base price. Accepts a PriceType, an id, or a code.
      def price_of_type(price_type, pricing_options = ::Spree::Config.default_pricing_options)
        SolidusAdvancedPricing.assert_advanced_pricing_options!(pricing_options)

        price_selector.price_for_options(
          pricing_options.with(price_type_id: SolidusAdvancedPricing.resolve_price_type_id(price_type))
        )
      end

      # The untyped price a sale or role-targeted price undercuts -- the value to
      # strike through in a storefront.
      def base_price(pricing_options = ::Spree::Config.default_pricing_options)
        price_of_type(nil, pricing_options)
      end

      # A MAP-restricted variant may carry no untyped price at all; fall back so
      # variant.price is never blank when some price exists.
      def default_price
        super || typed_fallback_price
      end

      private

      # Core calls default_price on the way into `price=`, so this runs in stores
      # that installed the gem and never registered its selector. Those get core's
      # PricingOptions, which has no price_type_id, and `with` would raise rather
      # than fall back -- breaking every `variant.price = ...`, product creation
      # included. Without the selector there are no typed prices to fall back to
      # anyway, so the right answer is core's: nothing.
      def typed_fallback_price
        pricing_options = ::Spree::Config.default_pricing_options
        return unless SolidusAdvancedPricing.advanced_pricing_options?(pricing_options)

        price_selector.price_for_options(pricing_options.with(price_type_id: :any))
      end

      ::Spree::Variant.prepend self
    end
  end
end
