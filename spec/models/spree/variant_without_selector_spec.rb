# frozen_string_literal: true

require "spec_helper"

# A store can install this gem and never register its price selector -- the
# README says the columns simply go unconsulted. Everything core does must then
# behave exactly as core does, because core's PricingOptions has no
# price_type_id and anything reaching for one blows up.
RSpec.describe "a store that has not registered the price selector" do
  around do |example|
    original = Spree::Config.variant_price_selector_class
    Spree::Config.variant_price_selector_class = Spree::Variant::PriceSelector
    example.run
    Spree::Config.variant_price_selector_class = original
  end

  it "uses core's pricing options, not this gem's" do
    expect(Spree::Config.default_pricing_options).to be_an_instance_of(Spree::Variant::PricingOptions)
    expect(Spree::Config.default_pricing_options).not_to be_a(SolidusAdvancedPricing::PricingOptions)
  end

  it "can create a product with a price" do
    product = create(:product, price: 100)

    expect(product.master.default_price.amount).to eq(100)
  end

  it "can set a price on an existing variant that has none" do
    variant = create(:variant)
    variant.prices.delete_all
    variant.reload

    expect { variant.price = 42 }.not_to raise_error
    expect(variant.default_price.amount).to eq(42)
  end

  it "returns nothing from default_price when the variant has no price" do
    variant = create(:variant)
    variant.prices.delete_all

    expect(variant.reload.default_price).to be_nil
  end

  it "still answers with_prices" do
    variant = create(:variant, price: 10)

    expect(Spree::Variant.with_prices).to include(variant)
  end

  it "explains itself rather than raising NoMethodError on price_of_type" do
    variant = create(:variant, price: 10)

    expect { variant.price_of_type("sale") }
      .to raise_error(SolidusAdvancedPricing::SelectorNotRegistered, /variant_price_selector_class/)
  end

  it "explains itself rather than raising NoMethodError on base_price" do
    variant = create(:variant, price: 10)

    expect { variant.base_price }.to raise_error(SolidusAdvancedPricing::SelectorNotRegistered)
  end
end
