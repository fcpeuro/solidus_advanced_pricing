# frozen_string_literal: true

require "spec_helper"

RSpec.feature "editing a price in the admin" do
  stub_authorization!

  let!(:wholesale_role) { create(:role, name: "wholesale") }
  let(:product) { create(:product, price: 100) }
  let(:price) { product.master.default_price }

  scenario "setting a type, role and notes" do
    visit spree.edit_admin_product_price_path(product, price)

    select "Wholesale", from: "price_price_type_id"
    select "wholesale", from: "price_role_id"
    fill_in "price_admin_notes", with: "Labor Day Sale 2026"
    click_button "Update"

    price.reload
    expect(price.price_type.code).to eq("wholesale")
    expect(price.role).to eq(wholesale_role)
    expect(price.admin_notes).to eq("Labor Day Sale 2026")
  end
end
