# frozen_string_literal: true

require_relative "lib/solidus_advanced_pricing/version"

Gem::Specification.new do |spec|
  spec.name = "solidus_advanced_pricing"
  spec.version = SolidusAdvancedPricing::VERSION
  spec.authors = ["Patrick McMorran"]
  spec.email = "pat.mcmorran@fcpeuro.com"

  spec.summary = "Price types, validity windows and role targeting for Solidus prices"
  spec.description = "Adds an admin-managed price type, an optional validity window, optional single-role targeting and internal admin notes to Spree::Price, selected through Solidus' own variant_price_selector_class seam."
  spec.homepage = "https://github.com/solidusio-contrib/solidus_advanced_pricing#readme"
  spec.license = "BSD-3-Clause"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/solidusio-contrib/solidus_advanced_pricing"
  spec.metadata["changelog_uri"] = "https://github.com/solidusio-contrib/solidus_advanced_pricing/blob/main/CHANGELOG.md"

  spec.required_ruby_version = ">= 3.1"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  files = Dir.chdir(__dir__) { `git ls-files -z`.split("\x0") }

  spec.files = files.grep_v(%r{^(test|spec|features)/})
  spec.bindir = "exe"
  spec.executables = files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "deface", "~> 1.9"
  spec.add_dependency "solidus_core", [">= 4.5", "< 5"]
  spec.add_dependency "solidus_support", "~> 0.14"

  spec.add_development_dependency "solidus_backend", [">= 4.5", "< 5"]
  spec.add_development_dependency "solidus_api", [">= 4.5", "< 5"]
  spec.add_development_dependency "solidus_dev_support", "~> 2.12"
  spec.add_development_dependency "db-query-matchers", "~> 0.12"
end
