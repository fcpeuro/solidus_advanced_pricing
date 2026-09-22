# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Variant, "#default_price fallback" do
  let(:variant) { create(:variant, price: 100) }
  let(:map_type) { SolidusAdvancedPricing::PriceType.find_by(code: "map") }
  let(:sale_type) { SolidusAdvancedPricing::PriceType.find_by(code: "sale") }
  let(:wholesale_role) { create(:role, name: "wholesale") }

  it "returns the map price when the variant has no untyped base price" do
    variant.prices.destroy_all
    create(:price, variant: variant, amount: 80, price_type: map_type)
    variant.reload
    expect(variant.price).to eq(80)
  end

  it "does not fall back when an untyped base price exists, even if a typed price is cheaper" do
    create(:price, variant: variant, amount: 70, price_type: sale_type)
    variant.reload
    expect(variant.price).to eq(100)
  end

  it "stays nil when the variant's only price is typed but expired" do
    freeze_time do
      variant.prices.destroy_all
      create(:price, variant: variant, amount: 80, price_type: map_type, valid_from: 5.days.ago, valid_to: 1.day.ago)
      variant.reload
      expect(variant.price).to be_nil
      expect(variant).not_to have_default_price
    end
  end

  it "stays nil when the variant's only price is typed but targeted at a role the caller lacks" do
    variant.prices.destroy_all
    create(:price, variant: variant, amount: 80, price_type: map_type, role: wholesale_role)
    variant.reload
    expect(variant.price).to be_nil
    expect(variant).not_to have_default_price
  end

  it "returns the cheapest of several typed prices when there is no base price" do
    variant.prices.destroy_all
    create(:price, variant: variant, amount: 80, price_type: map_type)
    create(:price, variant: variant, amount: 70, price_type: sale_type)
    variant.reload
    expect(variant.price).to eq(70)
  end
end
