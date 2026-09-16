# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidusAdvancedPricing::PriceType do
  it 'requires a name' do
    price_type = described_class.new(code: 'x')
    expect(price_type).not_to be_valid
    expect(price_type.errors[:name]).to be_present
  end

  it 'requires a unique code' do
    create(:price_type, code: 'wholesale')
    duplicate = described_class.new(name: 'Other', code: 'wholesale')
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:code]).to be_present
  end

  it 'is soft deletable' do
    price_type = create(:price_type)
    price_type.discard
    expect(described_class.all).not_to include(price_type)
    expect(described_class.with_discarded).to include(price_type)
  end
end
