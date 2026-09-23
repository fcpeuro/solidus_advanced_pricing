# frozen_string_literal: true

require "spec_helper"

RSpec.feature "price types in the new admin" do
  stub_authorization!

  before do
    skip "needs SolidusAdmin::ResourcesController (Solidus 4.5+)" unless defined?(SolidusAdmin::ResourcesController)
  end

  scenario "listing the seeded types" do
    visit "/admin/price_types"
    expect(page).to have_content("Wholesale")
    expect(page).to have_content("Clearance")
  end
end
