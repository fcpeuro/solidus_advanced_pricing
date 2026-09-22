# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Price do
  let(:now) { Time.zone.parse("2026-06-15 12:00:00") }
  let(:variant) { create(:variant) }
  let(:role) { create(:role, name: "wholesale") }

  describe ".valid_at" do
    let!(:open_ended) { create(:price, variant: variant) }
    let!(:current) { create(:price, variant: variant, valid_from: now - 1.day, valid_to: now + 1.day) }
    let!(:expired) { create(:price, variant: variant, valid_from: now - 5.days, valid_to: now - 1.day) }
    let!(:future) { create(:price, variant: variant, valid_from: now + 1.day) }
    # create(:variant) builds its own open-ended master price; restrict to this example's ids so it can't leak in.
    let(:candidates) { [open_ended, current, expired, future] }

    it "keeps open-ended and currently valid prices only" do
      expect(described_class.valid_at(now).where(id: candidates)).to contain_exactly(open_ended, current)
    end

    it "treats valid_to as exclusive" do
      expect(described_class.valid_at(now + 1.day).where(id: candidates)).not_to include(current)
    end
  end

  describe ".visible_to_roles" do
    let!(:untargeted) { create(:price, variant: variant, role: nil) }
    let!(:targeted) { create(:price, variant: variant, role: role) }
    # create(:variant) builds its own untargeted master price; restrict to this example's ids so it can't leak in.
    let(:candidates) { [untargeted, targeted] }

    it "returns only untargeted prices for a guest" do
      expect(described_class.visible_to_roles([]).where(id: candidates)).to contain_exactly(untargeted)
    end

    it "returns both for a customer holding the role" do
      expect(described_class.visible_to_roles([role.id]).where(id: candidates)).to contain_exactly(untargeted, targeted)
    end
  end

  describe ".for_price_type" do
    let(:wholesale_type) { SolidusAdvancedPricing::PriceType.find_by(code: "wholesale") }
    let!(:default_price) { create(:price, variant: variant) }
    let!(:wholesale_price) { create(:price, variant: variant, price_type: wholesale_type) }

    it "filters by type" do
      expect(described_class.for_price_type(wholesale_type)).to contain_exactly(wholesale_price)
    end
  end
end
