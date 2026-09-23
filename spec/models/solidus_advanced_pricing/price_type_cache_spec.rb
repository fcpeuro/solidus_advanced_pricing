# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PriceTypeCache do
  before { described_class.clear }

  describe ".position_for" do
    it "returns the position of a price type" do
      sale = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
      expect(described_class.position_for(sale.id)).to eq(sale.position)
    end

    it "still resolves a retired type" do
      sale = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
      sale.discard
      described_class.clear
      expect(described_class.position_for(sale.id)).to eq(sale.position)
    end

    it "falls back to 0 for an unknown id" do
      expect(described_class.position_for(-1)).to eq(0)
    end
  end

  describe ".id_for" do
    it "resolves a code to its id" do
      sale = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
      expect(described_class.id_for("sale")).to eq(sale.id)
    end

    it "accepts a symbol" do
      sale = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
      expect(described_class.id_for(:sale)).to eq(sale.id)
    end

    it "still resolves a retired type's code" do
      sale = SolidusAdvancedPricing::PriceType.find_by(code: "sale")
      sale.discard
      described_class.clear
      expect(described_class.id_for("sale")).to eq(sale.id)
    end

    it "returns nil for an unknown code" do
      expect(described_class.id_for("not-a-real-code")).to be_nil
    end
  end
end
