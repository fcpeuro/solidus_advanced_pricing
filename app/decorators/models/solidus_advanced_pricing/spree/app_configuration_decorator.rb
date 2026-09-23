# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module AppConfigurationDecorator
      def self.prepended(base)
        return if base.defined_preferences.include?(:advanced_pricing_cache_granularity)

        # Seconds of granularity for the time component of pricing cache keys.
        # 0 omits time from the key entirely; prices may then be cached past their window.
        base.preference :advanced_pricing_cache_granularity, :integer, default: 60
      end

      ::Spree::AppConfiguration.prepend self
    end
  end
end
