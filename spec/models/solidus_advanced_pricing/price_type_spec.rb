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

  it 'requires a code' do
    price_type = described_class.new(name: 'X')
    expect(price_type).not_to be_valid
    expect(price_type.errors[:code]).to be_present
  end

  it 'normalizes the code to lowercase' do
    expect(create(:price_type, code: '  Wholesale  ').code).to eq('wholesale')
  end

  it 'rejects a code differing only in case' do
    create(:price_type, code: 'sale')
    expect(described_class.new(name: 'Other', code: 'SALE')).not_to be_valid
  end

  it "keeps a discarded type's code reserved" do
    create(:price_type, code: 'retired').discard
    expect(described_class.new(name: 'Again', code: 'retired')).not_to be_valid
  end

  it 'allows only one default at a time' do
    first = create(:price_type, :default)
    second = create(:price_type, :default)
    expect(first.reload).not_to be_default
    expect(described_class.where(default: true)).to contain_exactly(second)
  end

  it 'promotes the only type to default automatically' do
    expect(create(:price_type).reload).to be_default
  end

  describe '.default' do
    it 'returns the flagged type' do
      default_type = create(:price_type, :default)
      expect(described_class.default).to eq(default_type)
    end

    it 'returns nil when the table is empty' do
      expect(described_class.default).to be_nil
    end
  end

  describe '.ordered' do
    it 'orders by position then id' do
      second = create(:price_type, position: 2)
      first = create(:price_type, position: 1)
      expect(described_class.ordered.to_a).to eq([first, second])
    end
  end

  it 'uses its name as its label' do
    expect(create(:price_type, name: 'Wholesale').to_s).to eq('Wholesale')
  end

  describe 'the default type' do
    let!(:default_type) { create(:price_type, code: 'default', default: true) }

    it 'cannot be discarded' do
      expect(default_type.discard).to be(false)
      expect(default_type.errors[:base]).to be_present
      expect(default_type.reload).to be_kept
    end

    it 're-promotes itself rather than leaving the store with no default' do
      default_type.update!(default: false)
      expect(default_type.reload).to be_default
    end

    it 'steps down when another type is made default' do
      create(:price_type, code: 'other', default: true)
      expect(default_type.reload).not_to be_default
    end
  end
end
