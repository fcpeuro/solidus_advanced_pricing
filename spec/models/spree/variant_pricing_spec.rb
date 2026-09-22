# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Variant, "advanced pricing" do
  it "uses the advanced price selector" do
    expect(Spree::Config.variant_price_selector_class).to eq(SolidusAdvancedPricing::PriceSelector)
  end

  it "delegates the pricing options class from the selector" do
    expect(Spree::Config.pricing_options_class).to eq(SolidusAdvancedPricing::PricingOptions)
  end
end
