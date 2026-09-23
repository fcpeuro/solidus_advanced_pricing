# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Role, "#destroy" do
  it "blocks destroying a role referenced by a kept price" do
    role = create(:role, name: "wholesale")
    create(:price, role: role)

    expect(role.destroy).to be(false)
    expect(role.errors[:base]).to be_present
    expect(described_class.exists?(role.id)).to be(true)
  end

  it "blocks destroying a role referenced only by a discarded price" do
    role = create(:role, name: "wholesale")
    price = create(:price, role: role)
    price.discard

    expect(role.destroy).to be(false)
    expect(role.errors[:base]).to be_present
  end

  it "blocks destroying a role referenced by a price type's default role" do
    role = create(:role, name: "employee")
    price_type = SolidusAdvancedPricing::PriceType.find_by(code: "employee")
    price_type.update!(role: role)

    expect(role.destroy).to be(false)
    expect(role.errors[:base]).to be_present
    expect(described_class.exists?(role.id)).to be(true)
  ensure
    price_type&.update!(role: nil)
  end

  it "blocks destroying a role referenced only by a discarded price type's default role" do
    role = create(:role, name: "employee")
    price_type = SolidusAdvancedPricing::PriceType.find_by(code: "employee")
    price_type.update!(role: role)
    price_type.discard

    expect(role.destroy).to be(false)
    expect(role.errors[:base]).to be_present
  ensure
    price_type&.update!(role: nil)
  end

  it "allows destroying a role nothing references" do
    role = create(:role, name: "unused")
    expect(role.destroy).not_to be(false)
    expect(described_class.exists?(role.id)).to be(false)
  end
end
