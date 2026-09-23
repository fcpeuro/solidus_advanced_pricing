# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::AppConfiguration do
  it "defaults the cache granularity to 60 seconds" do
    expect(Spree::Config.advanced_pricing_cache_granularity).to eq(60)
  end

  it "can be set to 0 to disable time bucketing" do
    # Spree::Config.preference_store is frozen for the test suite (solidus_dev_support
    # RSpec::Preferences.freeze_preferences), so direct assignment needs this wrapper.
    with_unfrozen_spree_preference_store do
      Spree::Config.advanced_pricing_cache_granularity = 0
      expect(Spree::Config.advanced_pricing_cache_granularity).to eq(0)
    end
  end
end
