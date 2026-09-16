# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'seeded price types' do
  it 'ships five types in order' do
    expect(SolidusAdvancedPricing::PriceType.ordered.pluck(:code)).to eq(
      %w[default wholesale sale clearance employee]
    )
  end

  it 'marks only default as the default' do
    expect(SolidusAdvancedPricing::PriceType.where(default: true).pluck(:code)).to eq(['default'])
  end
end
