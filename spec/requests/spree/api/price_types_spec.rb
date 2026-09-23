# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Price Types API" do
  # See prices_spec.rb: `spree_roles <<` never generates the key on its own.
  let(:admin) { create(:admin_user).tap(&:generate_spree_api_key!) }
  let(:customer) { create(:user).tap(&:generate_spree_api_key!) }

  describe "GET /api/price_types" do
    it "lists the seeded types in position order" do
      get "/api/price_types", headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      expect(response).to have_http_status(:ok)
      codes = JSON.parse(response.body)["price_types"].map { |type| type["code"] }
      expect(codes).to eq(%w[wholesale sale clearance employee map promotional])
    end

    it "serializes the fields a client needs to build a price payload" do
      role = Spree::Role.create!(name: "wholesale")
      SolidusAdvancedPricing::PriceType.find_by!(code: "wholesale").update!(role: role)

      get "/api/price_types", headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      wholesale = JSON.parse(response.body)["price_types"].find { |type| type["code"] == "wholesale" }
      expect(wholesale).to include("id", "code", "name", "position")
      expect(wholesale["role_id"]).to eq(role.id)
    end

    it "omits retired types" do
      SolidusAdvancedPricing::PriceType.find_by!(code: "promotional").discard

      get "/api/price_types", headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      codes = JSON.parse(response.body)["price_types"].map { |type| type["code"] }
      expect(codes).not_to include("promotional")
    end

    it "refuses a non-admin" do
      get "/api/price_types", headers: {"Authorization" => "Bearer #{customer.spree_api_key}"}

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
