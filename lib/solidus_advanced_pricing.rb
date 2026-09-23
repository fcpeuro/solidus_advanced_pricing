# frozen_string_literal: true

require "solidus_advanced_pricing/configuration"
require "solidus_advanced_pricing/version"
require "solidus_advanced_pricing/engine"

module SolidusAdvancedPricing
  # Raised when an advanced-pricing lookup is attempted in a store that never
  # registered this gem's price selector.
  class SelectorNotRegistered < StandardError
    def initialize(message = nil)
      super(message || <<~MESSAGE.strip)
        SolidusAdvancedPricing::PriceSelector is not registered, so pricing options
        carry no price type and this lookup cannot be answered. Set

          Spree::Config.variant_price_selector_class = "SolidusAdvancedPricing::PriceSelector"

        (the install generator writes this into config/initializers/solidus_advanced_pricing.rb).
      MESSAGE
    end
  end

  # Whether this gem's PricingOptions -- and therefore its selector -- is in play.
  # A store can install the gem and leave Spree::Config.variant_price_selector_class
  # alone; everything then has to behave exactly as core does.
  #
  # Tested by class, not by `respond_to?(:price_type_id)`: price_type_id is not a
  # reader on either class, it lives in desired_attributes. What actually differs
  # is that this gem's PricingOptions overrides `with` to merge arbitrary
  # attributes, where core's falls through to ActiveSupport's Object#with, which
  # public_sends every key it is given.
  def self.advanced_pricing_options?(pricing_options = ::Spree::Config.default_pricing_options)
    pricing_options.is_a?(SolidusAdvancedPricing::PricingOptions)
  end

  def self.assert_advanced_pricing_options!(pricing_options = ::Spree::Config.default_pricing_options)
    raise SelectorNotRegistered unless advanced_pricing_options?(pricing_options)
  end

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
