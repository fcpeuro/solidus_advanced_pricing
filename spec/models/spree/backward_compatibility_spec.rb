# frozen_string_literal: true

require "spec_helper"

RSpec.describe "backward compatibility with core pricing" do
  let(:variant) { create(:variant, price: 100) }

  it "returns the base price as the default price" do
    expect(variant.default_price.amount).to eq(100)
  end

  it "still answers #price" do
    expect(variant.price).to eq(100)
  end

  it "reports having a default price" do
    expect(variant).to have_default_price
  end

  it "builds a default price with no type and no role" do
    fresh = build(:variant)
    fresh.prices.destroy_all
    built = fresh.default_price_or_build
    expect(built.role_id).to be_nil
    expect(built.price_type_id).to be_nil
  end

  it "shows the admin the untargeted price, not a cheaper role-targeted one" do
    wholesale_role = create(:role, name: "wholesale")
    create(:price, variant: variant, amount: 60, role: wholesale_role)
    expect(variant.reload.default_price.amount).to eq(100)
  end

  it "shows the admin the base type, not a cheaper sale price" do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
    create(:price, variant: variant, amount: 70, price_type: sale_type)
    expect(variant.reload.default_price.amount).to eq(100)
  end

  it "prices a line item through the advanced options" do
    order = create(:order_with_line_items, line_items_count: 1)
    expect(order.line_items.first.price).to be_present
  end

  it "still computes price_difference_from_master" do
    product = create(:product, price: 100)
    expect { product.master.price_difference_from_master }.not_to raise_error
  end

  it "works with a plain core PricingOptions in with_prices" do
    variant
    core_options = ::Spree::Variant::PricingOptions.new(currency: "USD", country_iso: nil)
    expect { ::Spree::Variant.with_prices(core_options).to_a }.not_to raise_error
  end
end
