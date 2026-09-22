# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Prices API" do
  let!(:variant) { create(:variant, price: 100) }
  # admin_user's role is assigned via `spree_roles <<`, whose after_create
  # hook checks spree_roles before the in-memory collection reflects the
  # just-added role, so the auto-generated key never lands. Generate
  # explicitly rather than relying on that hook (or a new factory trait).
  let(:admin) { create(:admin_user).tap(&:generate_spree_api_key!) }
  let(:customer) { create(:user).tap(&:generate_spree_api_key!) }

  describe "GET /api/variants/:variant_id/prices" do
    it "lists prices with their advanced attributes" do
      get "/api/variants/#{variant.id}/prices", headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      expect(response).to have_http_status(:ok)
      price = JSON.parse(response.body)["prices"].first
      expect(price).to include("price_type_code", "role_id", "valid_from", "valid_to")
      expect(price["price_type_code"]).to eq("default")
    end

    it "includes admin_notes for a user who can update the price" do
      variant.default_price.update!(admin_notes: "Overstock Sale of 2012")
      get "/api/variants/#{variant.id}/prices", headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      price = JSON.parse(response.body)["prices"].first
      expect(price["admin_notes"]).to eq("Overstock Sale of 2012")
    end

    it "omits admin_notes for a non-admin" do
      variant.default_price.update!(admin_notes: "Overstock Sale of 2012")
      get "/api/variants/#{variant.id}/prices", headers: {"Authorization" => "Bearer #{customer.spree_api_key}"}

      if response.status == 200
        price = JSON.parse(response.body)["prices"].first
        expect(price).not_to have_key("admin_notes")
      else
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
