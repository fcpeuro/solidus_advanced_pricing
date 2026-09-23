# frozen_string_literal: true

require "spec_helper"

RSpec.feature "the admin prices index" do
  stub_authorization!

  let!(:wholesale_role) { create(:role, name: "wholesale") }
  let(:product) { create(:product, price: 100) }

  scenario "showing type and role for each price" do
    product.master.default_price.update!(
      price_type: SolidusAdvancedPricing::PriceType.find_by(code: "wholesale"),
      role: wholesale_role
    )

    visit spree.admin_product_prices_path(product)

    expect(page).to have_content("Wholesale")
    expect(page).to have_content("wholesale")
  end
end
