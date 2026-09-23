# frozen_string_literal: true

require "spec_helper"
require "generators/solidus_advanced_pricing/install/install_generator"

RSpec.describe SolidusAdvancedPricing::Generators::InstallGenerator do
  it "copies the initializer and the migrations" do
    expect(described_class.instance_methods).to include(:copy_initializer, :add_migrations)
  end

  it "sources its templates from the generator directory" do
    expect(described_class.source_root).to end_with("install/templates")
  end
end
