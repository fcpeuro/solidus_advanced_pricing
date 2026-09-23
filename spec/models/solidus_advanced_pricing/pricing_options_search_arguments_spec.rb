# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PricingOptions, "search_arguments" do
  let(:store) { create(:store) }
  let(:options) { described_class.from_context(double(current_spree_user: nil, current_store: store)) }

  it "matches the prices a storefront visitor can actually see" do
    create(:variant, price: 100)
    expect(::Spree::Price.where(options.search_arguments).count).to be > 0
  end

  it "drops an unpinned price type rather than filtering on NULL" do
    expect(options.search_arguments).not_to have_key(:price_type_id)
  end

  it "keeps a pinned price type" do
    pinned = described_class.new(price_type_id: 7)
    expect(pinned.search_arguments[:price_type_id]).to eq(7)
  end

  it "expands role_id to include untargeted prices" do
    expect(described_class.new(customer_role_ids: [3]).search_arguments[:role_id]).to eq([nil, 3])
  end

  it "does not mutate desired_attributes" do
    before_call = options.desired_attributes.dup
    options.search_arguments
    expect(options.desired_attributes).to eq(before_call)
  end
end
