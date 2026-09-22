# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::PermittedAttributes do
  it "permits the advanced pricing attributes on prices" do
    expect(described_class.price_attributes).to include(
      :price_type_id, :role_id, :valid_from, :valid_to, :admin_notes
    )
  end
end
