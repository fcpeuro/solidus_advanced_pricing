# frozen_string_literal: true

Spree::Config.variant_price_selector_class = "SolidusAdvancedPricing::PriceSelector"

# Seconds of granularity for the time component of pricing cache keys.
# Set to 0 to omit time from the key entirely.
# Spree::Config.advanced_pricing_cache_granularity = 60
