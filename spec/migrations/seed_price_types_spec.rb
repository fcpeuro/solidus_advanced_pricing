# frozen_string_literal: true

require "spec_helper"

RSpec.describe "seeded price types" do
  it "ships six types in order" do
    expect(SolidusAdvancedPricing::PriceType.ordered.pluck(:code)).to eq(
      %w[wholesale sale clearance employee map promotional]
    )
  end
end
