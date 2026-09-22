# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PriceSelector do
  subject(:selector) { described_class.new(variant) }

  let(:variant) { create(:variant, price: 100) }
  let(:now) { Time.zone.parse("2026-06-15 12:00:00") }
  let(:wholesale_role) { create(:role, name: "wholesale") }

  def options(**overrides)
    SolidusAdvancedPricing::PricingOptions.new(
      {currency: "USD", country_iso: nil, price_type_id: nil, at: now, customer_role_ids: []}.merge(overrides)
    )
  end

  it "exposes the matching pricing options class" do
    expect(described_class.pricing_options_class).to eq(SolidusAdvancedPricing::PricingOptions)
  end

  it "ignores prices in another currency" do
    create(:price, variant: variant, currency: "EUR", amount: 1)
    variant.reload
    expect(selector.price_for_options(options).currency).to eq("USD")
  end

  it "ignores an expired price" do
    create(:price, variant: variant, amount: 1, valid_from: now - 5.days, valid_to: now - 1.day)
    variant.reload
    expect(selector.price_for_options(options).amount).to eq(100)
  end

  it "ignores a future price" do
    create(:price, variant: variant, amount: 1, valid_from: now + 1.day)
    variant.reload
    expect(selector.price_for_options(options).amount).to eq(100)
  end

  it "uses a price whose window is currently open" do
    create(:price, variant: variant, amount: 80, valid_from: now - 1.day, valid_to: now + 1.day)
    variant.reload
    expect(selector.price_for_options(options).amount).to eq(80)
  end

  it "hides a role-targeted price from a guest" do
    create(:price, variant: variant, amount: 60, role: wholesale_role)
    variant.reload
    expect(selector.price_for_options(options).amount).to eq(100)
  end

  it "shows a role-targeted price to a customer holding that role" do
    create(:price, variant: variant, amount: 60, role: wholesale_role)
    variant.reload
    expect(selector.price_for_options(options(customer_role_ids: [wholesale_role.id])).amount).to eq(60)
  end

  it "returns nil when nothing is eligible" do
    variant.prices.each { |price| price.update!(valid_to: now - 1.day) }
    expect(selector.price_for_options(options)).to be_nil
  end

  it "lets every type compete when no type is pinned" do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
    create(:price, variant: variant, amount: 70, price_type: sale_type)
    variant.reload
    expect(selector.price_for_options(options).amount).to eq(70)
  end

  it "restricts to the pinned type when one is given" do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
    default_type = SolidusAdvancedPricing::PriceType.find_by(code: "default")
    create(:price, variant: variant, amount: 70, price_type: sale_type)
    variant.reload
    result = selector.price_for_options(options(price_type_id: default_type.id))
    expect(result.amount).to eq(100)
  end

  it "returns nil when candidates exist but none serve the requested country" do
    create(:country, iso: "DE")
    create(:country, iso: "FR")
    variant.prices.each { |price| price.update!(country_iso: "FR") }
    variant.reload
    expect(selector.price_for_options(options(country_iso: "DE"))).to be_nil
  end
end
