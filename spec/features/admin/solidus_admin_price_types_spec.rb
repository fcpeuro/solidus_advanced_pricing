# frozen_string_literal: true

require "spec_helper"

RSpec.feature "price types in the new admin" do
  stub_authorization!

  before do
    skip "solidus_admin not available" unless SolidusSupport.admin_available?
  end

  scenario "listing the seeded types" do
    visit "/admin/price_types"
    expect(page).to have_content("Wholesale")
    expect(page).to have_content("Clearance")
  end
end
