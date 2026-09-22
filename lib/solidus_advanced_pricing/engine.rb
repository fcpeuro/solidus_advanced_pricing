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

    # A decorator would re-append this on every `to_prepare` reload; an
    # initializer runs once at boot.
    initializer "solidus_advanced_pricing.menu_items" do
      next unless defined?(::SolidusAdmin::Config)
      next if ::SolidusAdmin::Config.menu_items.any? { |item| item[:key].to_s == "price_types" }

      ::SolidusAdmin::Config.menu_items << {
        key: "price_types",
        route: -> { solidus_admin.price_types_path },
        icon: "price-tag-3-line",
        position: 65
      }
    end
  end
end
