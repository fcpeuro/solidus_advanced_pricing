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

  it "backfills existing prices onto the default type" do
    expect(described_class.where(price_type_id: nil).count).to eq(0)
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
    expect(SolidusAdvancedPricing::PriceType.with_discarded).to include(sale_type)
  end
end
