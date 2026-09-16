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
end
