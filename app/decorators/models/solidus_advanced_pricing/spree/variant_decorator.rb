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

      ::Spree::Variant.prepend self
    end
  end
end
