# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PricingOptions, "cache keys" do
  let(:now) { Time.zone.parse("2026-06-15 12:00:00") }

  it "differs between a guest and a role-holding customer" do
    guest = described_class.new(at: now, customer_role_ids: [])
    wholesale = described_class.new(at: now, customer_role_ids: [7])
    expect(guest.cache_key).not_to eq(wholesale.cache_key)
  end

  it "does not depend on role order" do
    a = described_class.new(at: now, customer_role_ids: [7, 3])
    b = described_class.new(at: now, customer_role_ids: [3, 7])
    expect(a.cache_key).to eq(b.cache_key)
  end

  it "buckets time so nearby requests share a key" do
    a = described_class.new(at: now, customer_role_ids: [])
    b = described_class.new(at: now + 10.seconds, customer_role_ids: [])
    expect(a.cache_key).to eq(b.cache_key)
  end

  it "changes once the bucket rolls over" do
    a = described_class.new(at: now, customer_role_ids: [])
    b = described_class.new(at: now + 61.seconds, customer_role_ids: [])
    expect(a.cache_key).not_to eq(b.cache_key)
  end

  it "omits the time component when granularity is 0" do
    with_unfrozen_spree_preference_store do
      Spree::Config.advanced_pricing_cache_granularity = 0
      a = described_class.new(at: now, customer_role_ids: [])
      b = described_class.new(at: now + 1.year, customer_role_ids: [])
      expect(a.cache_key).to eq(b.cache_key)
    end
  end

  it "still varies by the attributes core keys on" do
    usd = described_class.new(currency: "USD", at: now, customer_role_ids: [])
    eur = described_class.new(currency: "EUR", at: now, customer_role_ids: [])
    expect(usd.cache_key).not_to eq(eur.cache_key)
  end
end
