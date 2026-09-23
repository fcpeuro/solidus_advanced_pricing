# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Price do
  it "has the advanced pricing columns" do
    expect(described_class.column_names).to include(
      "price_type_id", "role_id", "valid_from", "valid_to", "admin_notes"
    )
  end

  it "builds a price with no type as valid, with price_type_id nil" do
    price = build(:price, price_type: nil)
    expect(price).to be_valid
    expect(price.price_type_id).to be_nil
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

  describe "#effective_role_id" do
    let(:price_role) { create(:role, name: "wholesale") }
    let(:type_role) { create(:role, name: "employee") }
    let(:price_type) { create(:price_type, role: type_role) }

    it "prefers the price's own role over the type's" do
      price = create(:price, price_type: price_type, role: price_role)
      expect(price.effective_role_id).to eq(price_role.id)
    end

    it "falls back to the type's role when the price's own role is nil" do
      price = create(:price, price_type: price_type, role: nil)
      expect(price.effective_role_id).to eq(type_role.id)
    end

    it "is nil when neither the price nor its type has a role" do
      untyped = create(:price_type, role: nil)
      price = create(:price, price_type: untyped, role: nil)
      expect(price.effective_role_id).to be_nil
    end

    it "is nil for an untyped price with no role of its own" do
      price = create(:price, price_type: nil, role: nil)
      expect(price.effective_role_id).to be_nil
    end
  end
end
