# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PriceType do
  it "requires a name" do
    price_type = described_class.new(code: "x")
    expect(price_type).not_to be_valid
    expect(price_type.errors[:name]).to be_present
  end

  it "requires a unique code" do
    create(:price_type, code: "promo")
    duplicate = described_class.new(name: "Other", code: "promo")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:code]).to be_present
  end

  it "is soft deletable" do
    price_type = create(:price_type)
    price_type.discard
    expect(described_class.all).not_to include(price_type)
    expect(described_class.with_discarded).to include(price_type)
  end

  it "requires a code" do
    price_type = described_class.new(name: "X")
    expect(price_type).not_to be_valid
    expect(price_type.errors[:code]).to be_present
  end

  it "normalizes the code to lowercase" do
    expect(create(:price_type, code: "  Bespoke  ").code).to eq("bespoke")
  end

  it "rejects a code differing only in case" do
    create(:price_type, code: "bogo")
    expect(described_class.new(name: "Other", code: "BOGO")).not_to be_valid
  end

  it "keeps a discarded type's code reserved" do
    create(:price_type, code: "retired").discard
    expect(described_class.new(name: "Again", code: "retired")).not_to be_valid
  end

  describe ".ordered" do
    it "orders by position then id" do
      second = create(:price_type, position: 2)
      first = create(:price_type, position: 1)
      expect(described_class.where(id: [first.id, second.id]).ordered.to_a).to eq([first, second])
    end
  end

  it "uses its name as its label" do
    expect(create(:price_type, name: "Wholesale").to_s).to eq("Wholesale")
  end
end
