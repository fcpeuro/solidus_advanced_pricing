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
      expect(price["price_type_code"]).to be_nil
    end

    it "includes admin_notes for a user who can update the price" do
      variant.default_price.update!(admin_notes: "Overstock Sale of 2012")
      get "/api/variants/#{variant.id}/prices", headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      price = JSON.parse(response.body)["prices"].first
      expect(price["admin_notes"]).to eq("Overstock Sale of 2012")
    end

    it "omits deleted prices by default" do
      deleted = variant.prices.create!(amount: 50, currency: variant.default_price.currency)
      deleted.discard

      get "/api/variants/#{variant.id}/prices", headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      expect(JSON.parse(response.body)["prices"].map { |price| price["id"] }).not_to include(deleted.id)
    end

    it "includes deleted prices with show_deleted" do
      deleted = variant.prices.create!(amount: 50, currency: variant.default_price.currency)
      deleted.discard

      get "/api/variants/#{variant.id}/prices?show_deleted=true",
        headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      expect(JSON.parse(response.body)["prices"].map { |price| price["id"] }).to include(deleted.id)
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

  describe "POST /api/variants/:variant_id/prices" do
    # `**attributes` rather than a positional hash: Ruby 3 would bind a bare
    # `post_price(amount: "1")` to the `user:` keyword and leave the positional
    # argument missing.
    def post_price(user: admin, **attributes)
      post "/api/variants/#{variant.id}/prices",
        params: {price: attributes},
        headers: {"Authorization" => "Bearer #{user.spree_api_key}"}
    end

    it "creates an untyped price" do
      post_price(amount: "42.00")

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["amount"]).to eq("42.0")
      expect(body["price_type_code"]).to be_nil
      expect(variant.prices.reload.map(&:amount)).to include(42)
    end

    it "defaults currency to the store's when it is not given" do
      post_price(amount: "42.00")

      expect(JSON.parse(response.body)["currency"]).to eq(Spree::Config.default_pricing_options.currency)
    end

    it "creates a typed price from a price_type_code" do
      post_price(amount: "35.00", price_type_code: "wholesale")

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["price_type_code"]).to eq("wholesale")
    end

    it "creates a typed price from a price_type_id" do
      sale = SolidusAdvancedPricing::PriceType.find_by!(code: "sale")
      post_price(amount: "35.00", price_type_id: sale.id)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["price_type_code"]).to eq("sale")
    end

    it "treats an explicitly blank price_type_code as the base price" do
      post_price(amount: "35.00", price_type_code: "")

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["price_type_code"]).to be_nil
    end

    it "creates a role-targeted price inside a validity window" do
      role = Spree::Role.create!(name: "employee")
      post_price(
        amount: "30.00",
        price_type_code: "employee",
        role_id: role.id,
        valid_from: "2026-01-01T00:00:00Z",
        valid_to: "2026-02-01T00:00:00Z"
      )

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["role_id"]).to eq(role.id)
      expect(body["valid_from"]).to be_present
    end

    it "rejects an unknown price_type_code" do
      post_price(amount: "35.00", price_type_code: "nonexistent")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("nonexistent")
      expect(variant.prices.reload.count).to eq(1)
    end

    it "rejects a payload carrying both price_type_id and price_type_code" do
      sale = SolidusAdvancedPricing::PriceType.find_by!(code: "sale")
      post_price(amount: "35.00", price_type_id: sale.id, price_type_code: "sale")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(variant.prices.reload.count).to eq(1)
    end

    it "surfaces model validation failures" do
      post_price(amount: "35.00", valid_from: "2026-02-01T00:00:00Z", valid_to: "2026-01-01T00:00:00Z")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(variant.prices.reload.count).to eq(1)
    end

    it "refuses a non-admin" do
      post_price(user: customer, amount: "1.00")

      expect(response).to have_http_status(:unauthorized)
      expect(variant.prices.reload.count).to eq(1)
    end
  end

  describe "PATCH /api/variants/:variant_id/prices/:id" do
    let(:price) { variant.default_price }

    def patch_price(user: admin, **attributes)
      patch "/api/variants/#{variant.id}/prices/#{price.id}",
        params: {price: attributes},
        headers: {"Authorization" => "Bearer #{user.spree_api_key}"}
    end

    it "updates the amount" do
      patch_price(amount: "88.00")

      expect(response).to have_http_status(:ok)
      expect(price.reload.amount).to eq(88)
    end

    it "updates admin_notes" do
      patch_price(admin_notes: "Matched a competitor")

      expect(response).to have_http_status(:ok)
      expect(price.reload.admin_notes).to eq("Matched a competitor")
    end

    it "refuses to retype an existing price" do
      sale = SolidusAdvancedPricing::PriceType.find_by!(code: "sale")
      patch_price(price_type_id: sale.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(price.reload.price_type_id).to be_nil
    end

    it "accepts a read-modify-write that resends the unchanged price type" do
      typed = variant.prices.create!(
        amount: 50,
        currency: variant.default_price.currency,
        price_type: SolidusAdvancedPricing::PriceType.find_by!(code: "sale")
      )

      patch "/api/variants/#{variant.id}/prices/#{typed.id}",
        params: {price: {amount: "49.00", price_type_id: typed.price_type_id}},
        headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      expect(response).to have_http_status(:ok)
      expect(typed.reload.amount).to eq(49)
    end

    it "refuses a non-admin" do
      patch_price(user: customer, amount: "1.00")

      expect(response).to have_http_status(:unauthorized)
      expect(price.reload.amount).to eq(100)
    end
  end

  describe "DELETE /api/variants/:variant_id/prices/:id" do
    let!(:price) do
      variant.prices.create!(
        amount: 50,
        currency: variant.default_price.currency,
        price_type: SolidusAdvancedPricing::PriceType.find_by!(code: "sale")
      )
    end

    it "soft deletes the price" do
      delete "/api/variants/#{variant.id}/prices/#{price.id}",
        headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      expect(response).to have_http_status(:no_content)
      expect(Spree::Price.with_discarded.find(price.id).deleted_at).to be_present
      expect(variant.prices.kept.reload).not_to include(price)
    end

    it "drops the price from the listing afterwards" do
      delete "/api/variants/#{variant.id}/prices/#{price.id}",
        headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}
      get "/api/variants/#{variant.id}/prices",
        headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      expect(JSON.parse(response.body)["prices"].map { |p| p["id"] }).not_to include(price.id)
    end

    it "refuses to update a price that has been deleted" do
      price.discard

      patch "/api/variants/#{variant.id}/prices/#{price.id}",
        params: {price: {amount: "1.00"}},
        headers: {"Authorization" => "Bearer #{admin.spree_api_key}"}

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a non-admin" do
      delete "/api/variants/#{variant.id}/prices/#{price.id}",
        headers: {"Authorization" => "Bearer #{customer.spree_api_key}"}

      expect(response).to have_http_status(:unauthorized)
      expect(price.reload.deleted_at).to be_nil
    end
  end
end
