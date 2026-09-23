# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Variant, ".with_prices" do
  let(:now) { Time.zone.parse("2026-06-15 12:00:00") }
  let(:wholesale_role) { create(:role, name: "wholesale") }

  def options(**overrides)
    SolidusAdvancedPricing::PricingOptions.new(
      {currency: "USD", country_iso: nil, price_type_id: nil, at: now, customer_role_ids: []}.merge(overrides)
    )
  end

  it "excludes a variant whose only price has expired" do
    variant = create(:variant, price: 100)
    variant.prices.each { |price| price.update!(valid_to: now - 1.day) }
    expect(described_class.with_prices(options)).not_to include(variant)
  end

  it "includes a variant with an open-ended price" do
    variant = create(:variant, price: 100)
    expect(described_class.with_prices(options)).to include(variant)
  end

  it "excludes a variant priced only for a role the customer lacks" do
    variant = create(:variant, price: 100)
    variant.prices.each { |price| price.update!(role: wholesale_role) }
    expect(described_class.with_prices(options)).not_to include(variant)
  end

  it "includes that variant for a customer holding the role" do
    variant = create(:variant, price: 100)
    variant.prices.each { |price| price.update!(role: wholesale_role) }
    expect(
      described_class.with_prices(options(customer_role_ids: [wholesale_role.id]))
    ).to include(variant)
  end

  it "excludes a variant whose only price inherits a role from its price type, for a guest" do
    employee_type = SolidusAdvancedPricing::PriceType.find_by(code: "employee")
    employee_type.update!(role: wholesale_role)
    variant = create(:variant)
    variant.prices.destroy_all
    variant.prices.create!(currency: "USD", amount: 100, price_type: employee_type, role: nil)

    expect(described_class.with_prices(options)).not_to include(variant)
  ensure
    employee_type&.update!(role: nil)
  end

  it "includes that variant for a customer holding the type's default role" do
    employee_type = SolidusAdvancedPricing::PriceType.find_by(code: "employee")
    employee_type.update!(role: wholesale_role)
    variant = create(:variant)
    variant.prices.destroy_all
    variant.prices.create!(currency: "USD", amount: 100, price_type: employee_type, role: nil)

    expect(
      described_class.with_prices(options(customer_role_ids: [wholesale_role.id]))
    ).to include(variant)
  ensure
    employee_type&.update!(role: nil)
  end
end
