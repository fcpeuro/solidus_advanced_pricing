# frozen_string_literal: true

require "spec_helper"

RSpec.feature "the admin price form" do
  stub_authorization!

  let!(:wholesale_role) { create(:role, name: "wholesale") }
  let(:product) { create(:product, price: 100) }
  let(:price) { product.master.default_price }

  scenario "choosing a price type when creating a price" do
    visit spree.new_admin_product_price_path(product)

    select product.master.descriptive_name, from: "price_variant_id"
    select "Wholesale", from: "price_price_type_id"
    fill_in "price_price", with: "80"
    click_button "Create"

    expect(product.master.prices.reload.find_by(amount: 80).price_type.code).to eq("wholesale")
  end

  scenario "leaving a new price untyped" do
    visit spree.new_admin_product_price_path(product)

    select product.master.descriptive_name, from: "price_variant_id"
    select "Base price (no type)", from: "price_price_type_id"
    fill_in "price_price", with: "90"
    click_button "Create"

    expect(product.master.prices.reload.find_by(amount: 90).price_type_id).to be_nil
  end

  scenario "setting role and notes on an existing price" do
    visit spree.edit_admin_product_price_path(product, price)

    select "wholesale", from: "price_role_id"
    fill_in "price_admin_notes", with: "Labor Day Sale 2026"
    click_button "Update"

    price.reload
    expect(price.role).to eq(wholesale_role)
    expect(price.admin_notes).to eq("Labor Day Sale 2026")
  end

  scenario "locks the price type once the price exists" do
    visit spree.edit_admin_product_price_path(product, price)

    expect(page).to have_field("price_price_type_id", disabled: true)
  end
end
