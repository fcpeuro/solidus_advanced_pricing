# frozen_string_literal: true

module SolidusAdvancedPricing
  # Filter -> country bucket -> cheapest. Role is eligibility only, never specificity:
  # a role-targeted price set above the untargeted price therefore never applies.
  class PriceSelector < ::Spree::Variant::PriceSelector
    def self.pricing_options_class
      SolidusAdvancedPricing::PricingOptions
    end

    def price_for_options(price_options)
      candidates = eligible_prices(price_options)
      return nil if candidates.empty?

      cheapest(bucket_by_country(candidates, price_options.country_iso))
    end

    private

    def eligible_prices(price_options)
      wanted_type = price_options.desired_attributes[:price_type_id]

      variant.prices.select do |price|
        kept?(price) &&
          price.currency == price_options.currency &&
          matches_type?(price, wanted_type) &&
          valid_at?(price, price_options.at) &&
          visible_to?(price, price_options.customer_role_ids)
      end
    end

    def kept?(price)
      variant.discarded? || price.kept?
    end

    # nil = untyped base prices only (the admin's view); :any = every type competes
    # (a customer's view); an id = that type only.
    def matches_type?(price, wanted_type)
      return true if wanted_type == :any

      price.price_type_id == wanted_type
    end

    def valid_at?(price, time)
      return true if time.nil?

      (price.valid_from.nil? || price.valid_from <= time) &&
        (price.valid_to.nil? || price.valid_to > time)
    end

    def visible_to?(price, customer_role_ids)
      price.role_id.nil? || customer_role_ids.include?(price.role_id)
    end

    # Country is specificity, not competition: a country-specific price beats the
    # any-country fallback even when the fallback is cheaper.
    def bucket_by_country(candidates, country_iso)
      specific = candidates.select { |price| price.country_iso == country_iso && !price.country_iso.nil? }
      specific.presence || candidates.select { |price| price.country_iso.nil? }
    end

    def cheapest(candidates)
      candidates.min_by do |price|
        [
          price.amount,
          SolidusAdvancedPricing::PriceTypeCache.position_for(price.price_type_id),
          -(price.updated_at || Time.zone.now).to_i,
          -(price.id || Float::INFINITY)
        ]
      end
    end
  end
end
