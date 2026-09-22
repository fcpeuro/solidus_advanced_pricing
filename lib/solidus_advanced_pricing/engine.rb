# frozen_string_literal: true

require "solidus_core"
require "solidus_support"
# Not auto-required by Bundler: `gemspec` in the Gemfile folds runtime deps
# into a single pseudo-dependency, so Deface's ActionView hook never loads
# unless something requires it explicitly.
require "deface"

module SolidusAdvancedPricing
  class Engine < Rails::Engine
    include SolidusSupport::EngineExtensions

    isolate_namespace ::Spree

    engine_name "solidus_advanced_pricing"

    # use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
