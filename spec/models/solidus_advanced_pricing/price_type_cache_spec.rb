# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PriceTypeCache do
  before { described_class.clear }

  it "returns the id of the default price type" do
    expected = SolidusAdvancedPricing::PriceType.find_by(code: "default").id
    expect(described_class.default_id).to eq(expected)
  end

  it "does not query again on a second call" do
    described_class.default_id
    expect { described_class.default_id }.not_to make_database_queries
  end

  it "is cleared when a price type is saved" do
    described_class.default_id
    create(:price_type)
    expect(described_class.instance_variable_defined?(:@default_id)).to be(false)
  end

  it "caches a nil result instead of re-querying forever" do
    SolidusAdvancedPricing::PriceType.with_discarded.update_all(default: false)
    described_class.clear
    described_class.default_id
    expect { described_class.default_id }.not_to make_database_queries
  end

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
end
