# frozen_string_literal: true

require "solidus_advanced_pricing/configuration"
require "solidus_advanced_pricing/version"
require "solidus_advanced_pricing/engine"

module SolidusAdvancedPricing
  # nil stays nil (the base price); a PriceType or id passes through; a code resolves.
  def self.resolve_price_type_id(price_type)
    case price_type
    when nil then nil
    when ::SolidusAdvancedPricing::PriceType then price_type.id
    when Integer then price_type
    else
      SolidusAdvancedPricing::PriceTypeCache.id_for(price_type) ||
        raise(ArgumentError, "no price type with code #{price_type.inspect}")
    end
  end
end
