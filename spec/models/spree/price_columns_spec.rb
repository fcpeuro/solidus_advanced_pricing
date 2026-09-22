# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Price do
  it "has the advanced pricing columns" do
    expect(described_class.column_names).to include(
      "price_type_id", "role_id", "valid_from", "valid_to", "admin_notes"
    )
  end

  it "defaults a new price to the default price type" do
    price = create(:price)
    expect(price.price_type.code).to eq("default")
  end

  it "keeps its price type after the type is retired" do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
    price = create(:price, price_type: sale_type)
    sale_type.discard
    expect(price.reload.price_type).to eq(sale_type)
  end

  it "blocks destroying a type that a discarded price still references" do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
    price = create(:price, price_type: sale_type)
    price.discard
    expect(sale_type.destroy).to be(false)
    expect(sale_type.errors[:base]).to be_present
    expect(SolidusAdvancedPricing::PriceType.with_discarded).to include(sale_type)
  end

  it "round-trips the targeting role" do
    role = create(:role, name: "wholesale")
    expect(create(:price, role: role).reload.role).to eq(role)
  end

  it "defaults to no role, meaning every customer" do
    expect(create(:price).role).to be_nil
  end

  it "persists the validity window and admin notes" do
    price = create(
      :price,
      valid_from: Time.zone.parse("2026-01-01"),
      valid_to: Time.zone.parse("2026-02-01"),
      admin_notes: "Overstock Sale of 2012"
    )
    price.reload
    expect(price.valid_from).to eq(Time.zone.parse("2026-01-01"))
    expect(price.valid_to).to eq(Time.zone.parse("2026-02-01"))
    expect(price.admin_notes).to eq("Overstock Sale of 2012")
  end

  it "reports a missing price type exactly once" do
    price = build(:price)
    allow(SolidusAdvancedPricing::PriceTypeCache).to receive(:default_id).and_return(nil)
    price.price_type_id = nil
    price.valid?
    expect(price.errors[:price_type].size).to eq(1)
  end

  it "does not clobber an explicitly assigned price type" do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
    price = create(:price, price_type: sale_type)
    price.update!(amount: 42)
    expect(price.reload.price_type).to eq(sale_type)
  end

  it "blocks destroying a type that a kept price references" do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
    create(:price, price_type: sale_type)
    expect(sale_type.destroy).to be(false)
    expect(sale_type.errors[:base]).to be_present
  end
end
