# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Price do
  it "rejects a window that ends before it starts" do
    price = build(:price, valid_from: Time.zone.parse("2026-02-01"), valid_to: Time.zone.parse("2026-01-01"))
    expect(price).not_to be_valid
    expect(price.errors[:valid_to]).to be_present
  end

  it "accepts a window that ends after it starts" do
    price = build(:price, valid_from: Time.zone.parse("2026-01-01"), valid_to: Time.zone.parse("2026-02-01"))
    expect(price).to be_valid
  end

  it "accepts an open-ended window" do
    expect(build(:price, valid_from: nil, valid_to: nil)).to be_valid
    expect(build(:price, valid_from: Time.current, valid_to: nil)).to be_valid
    expect(build(:price, valid_from: nil, valid_to: Time.current)).to be_valid
  end
end
