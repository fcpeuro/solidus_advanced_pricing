# frozen_string_literal: true

require "spec_helper"

RSpec.feature "managing price types" do
  stub_authorization!

  scenario "listing the seeded types" do
    visit spree.admin_price_types_path
    expect(page).to have_content("Wholesale")
    expect(page).to have_content("Clearance")
  end

  scenario "creating a type" do
    visit spree.new_admin_price_type_path
    fill_in "price_type_name", with: "Dealer"
    fill_in "price_type_code", with: "dealer"
    click_button "Create"

    expect(SolidusAdvancedPricing::PriceType.find_by(code: "dealer")).to be_present
  end

  scenario "refuses to delete the default type" do
    default_type = SolidusAdvancedPricing::PriceType.find_by(code: "default")
    expect(default_type.discard).to be(false)
  end
end
