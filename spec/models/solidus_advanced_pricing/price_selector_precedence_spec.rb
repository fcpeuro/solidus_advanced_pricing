# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PriceSelector, "precedence" do
  subject(:selector) { described_class.new(variant) }

  let(:variant) { create(:variant, price: 100) }
  let(:now) { Time.zone.parse("2026-06-15 12:00:00") }
  let(:wholesale_role) { create(:role, name: "wholesale") }

  def options(**overrides)
    SolidusAdvancedPricing::PricingOptions.new(
      {currency: "USD", country_iso: nil, price_type_id: nil, at: now, customer_role_ids: []}.merge(overrides)
    )
  end

  it "prefers a country-specific price over a cheaper any-country price" do
    create(:country, iso: "DE")
    create(:price, variant: variant, country_iso: "DE", amount: 150)
    variant.reload
    expect(selector.price_for_options(options(country_iso: "DE")).amount).to eq(150)
  end

  it "falls back to the any-country price when no country price exists" do
    create(:country, iso: "DE")
    variant.reload
    expect(selector.price_for_options(options(country_iso: "DE")).amount).to eq(100)
  end

  it "picks the cheapest within the winning country bucket" do
    create(:price, variant: variant, amount: 70)
    create(:price, variant: variant, amount: 85)
    variant.reload
    expect(selector.price_for_options(options).amount).to eq(70)
  end

  it "never applies a role price set above the untargeted price" do
    create(:price, variant: variant, amount: 120, role: wholesale_role)
    variant.reload
    result = selector.price_for_options(options(customer_role_ids: [wholesale_role.id]))
    expect(result.amount).to eq(100)
  end

  it "lets a customer holding two roles take the cheaper of the two" do
    employee_role = create(:role, name: "employee")
    create(:price, variant: variant, amount: 60, role: wholesale_role)
    create(:price, variant: variant, amount: 50, role: employee_role)
    variant.reload
    result = selector.price_for_options(
      options(customer_role_ids: [wholesale_role.id, employee_role.id])
    )
    expect(result.amount).to eq(50)
  end
end
