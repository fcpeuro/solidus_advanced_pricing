# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Price Batch API" do
  # See prices_spec.rb: `spree_roles <<` never generates the key on its own.
  let(:admin) { create(:admin_user).tap(&:generate_spree_api_key!) }
  let(:customer) { create(:user).tap(&:generate_spree_api_key!) }

  let!(:first) { create(:variant, price: 100) }
  let!(:second) { create(:variant, price: 200) }

  let(:currency) { Spree::Config.default_pricing_options.currency }

  def post_batch(prices:, user: admin, **options)
    post "/api/prices/batch",
      params: {prices: prices}.merge(options),
      headers: {"Authorization" => "Bearer #{user.spree_api_key}"}
  end

  def body = JSON.parse(response.body)

  describe "POST /api/prices/batch" do
    it "creates prices across several variants in one call" do
      post_batch(prices: [
        {variant_id: first.id, amount: "35.00", price_type_code: "sale"},
        {variant_id: second.id, amount: "45.00", price_type_code: "sale"}
      ])

      expect(response).to have_http_status(:ok)
      expect(body["summary"]).to eq("created" => 2)
      expect(first.prices.kept.count).to eq(2)
      expect(second.prices.kept.count).to eq(2)
    end

    it "addresses a variant by sku" do
      post_batch(prices: [{sku: first.sku, amount: "35.00", price_type_code: "sale"}])

      expect(body["summary"]).to eq("created" => 1)
      expect(body["results"].first["variant_id"]).to eq(first.id)
    end

    it "is idempotent on the natural key" do
      row = {variant_id: first.id, amount: "35.00", price_type_code: "sale"}

      post_batch(prices: [row])
      expect(body["summary"]).to eq("created" => 1)

      post_batch(prices: [row])
      expect(body["summary"]).to eq("unchanged" => 1)
      expect(first.prices.kept.where.not(price_type_id: nil).count).to eq(1)
    end

    it "updates the amount of a price it matches" do
      post_batch(prices: [{variant_id: first.id, amount: "35.00", price_type_code: "sale"}])
      post_batch(prices: [{variant_id: first.id, amount: "30.00", price_type_code: "sale"}])

      expect(body["summary"]).to eq("updated" => 1)
      expect(first.prices.kept.find_by(price_type_id: sale.id).amount).to eq(30)
    end

    it "treats a different validity window as a different price" do
      post_batch(prices: [
        {variant_id: first.id, amount: "35.00", price_type_code: "sale", valid_from: "2026-11-27T00:00:00Z"},
        {variant_id: first.id, amount: "30.00", price_type_code: "sale", valid_from: "2026-12-20T00:00:00Z"}
      ])

      expect(body["summary"]).to eq("created" => 2)
    end

    it "treats a different role as a different price" do
      role = Spree::Role.create!(name: "wholesale")

      post_batch(prices: [
        {variant_id: first.id, amount: "35.00", price_type_code: "sale"},
        {variant_id: first.id, amount: "30.00", price_type_code: "sale", role_id: role.id}
      ])

      expect(body["summary"]).to eq("created" => 2)
    end

    it "reports a duplicate natural key inside one payload rather than applying it twice" do
      post_batch(prices: [
        {variant_id: first.id, amount: "35.00", price_type_code: "sale"},
        {variant_id: first.id, amount: "30.00", price_type_code: "sale"}
      ])

      expect(body["summary"]).to eq("created" => 1, "error" => 1)
      expect(body["results"].last["errors"].first).to include("duplicate of row 0")
      expect(first.prices.kept.find_by(price_type_id: sale.id).amount).to eq(35)
    end

    it "applies good rows and reports bad ones" do
      post_batch(prices: [
        {variant_id: first.id, amount: "35.00", price_type_code: "sale"},
        {variant_id: first.id, amount: "30.00", price_type_code: "nonexistent"},
        {variant_id: 0, amount: "30.00"},
        {amount: "30.00"},
        {variant_id: second.id, sku: second.sku, amount: "30.00"}
      ])

      expect(body["summary"]).to eq("created" => 1, "error" => 4)
      messages = body["results"].filter_map { |result| result["errors"]&.first }
      expect(messages).to include(
        a_string_including("no price type with code"),
        a_string_including("no variant with id 0"),
        a_string_including("variant_id or sku is required"),
        a_string_including("not both")
      )
      expect(first.prices.kept.count).to eq(2)
    end

    it "surfaces model validation failures per row without losing the batch" do
      post_batch(prices: [
        {variant_id: first.id, amount: "35.00", price_type_code: "sale"},
        {variant_id: second.id, amount: "30.00", valid_from: "2026-02-01T00:00:00Z", valid_to: "2026-01-01T00:00:00Z"}
      ])

      expect(body["summary"]).to eq("created" => 1, "error" => 1)
      expect(body["results"].last["errors"].join).to match(/valid to/i)
    end

    it "refuses a non-admin" do
      post_batch(prices: [{variant_id: first.id, amount: "1.00"}], user: customer)

      expect(response).to have_http_status(:unauthorized)
      expect(first.prices.kept.count).to eq(1)
    end

    it "rejects a payload over the row limit before touching anything" do
      allow(SolidusAdvancedPricing.config).to receive(:batch_row_limit).and_return(2)

      post_batch(prices: Array.new(3) { {variant_id: first.id, amount: "1.00"} })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["error"]).to include("limited to 2 rows")
      expect(first.prices.kept.count).to eq(1)
    end

    it "rejects an unknown mode" do
      post_batch(prices: [{variant_id: first.id, amount: "1.00"}], mode: "obliterate")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(first.prices.kept.count).to eq(1)
    end
  end

  describe "dry_run" do
    it "reports what it would do and writes nothing" do
      post_batch(
        prices: [
          {variant_id: first.id, amount: "35.00", price_type_code: "sale"},
          {variant_id: second.id, amount: "30.00", price_type_code: "nonexistent"}
        ],
        dry_run: true
      )

      expect(body["dry_run"]).to be(true)
      expect(body["summary"]).to eq("created" => 1, "error" => 1)
      expect(first.prices.kept.count).to eq(1)
      expect(Spree::Price.with_discarded.where(price_type_id: sale.id)).to be_empty
    end

    it "does not report ids that are about to stop existing" do
      post_batch(prices: [{variant_id: first.id, amount: "35.00", price_type_code: "sale"}], dry_run: true)

      expect(body["results"].first["status"]).to eq("created")
      expect(body["results"].first).not_to have_key("price_id")
    end
  end

  describe "replace mode" do
    # The leftover carries a valid_from so it is a genuinely different row from
    # the one the payload sends -- give it the same natural key and upsert
    # matches it, which is the behaviour the tests above already pin.
    let(:window_start) { 1.week.ago.change(usec: 0) }

    let!(:stale) do
      first.prices.create!(amount: 60, currency: currency, price_type: sale, valid_from: window_start)
    end

    it "matches a stored sub-second valid_from from a truncated payload" do
      precise = 3.days.from_now.change(usec: 123_456)
      row = second.prices.create!(amount: 90, currency: currency, price_type: sale, valid_from: precise)

      post_batch(prices: [
        {variant_id: second.id, amount: "85.00", price_type_code: "sale", valid_from: precise.iso8601}
      ])

      expect(body["summary"]).to eq("updated" => 1)
      expect(row.reload.amount).to eq(85)
    end

    def discarded?(price) = Spree::Price.with_discarded.find(price.id).deleted_at.present?

    it "discards prices of a named type that the payload left out" do
      post_batch(prices: [{variant_id: first.id, amount: "35.00", price_type_code: "sale"}], mode: "replace")

      expect(body["summary"]).to eq("created" => 1, "deleted" => 1)
      expect(discarded?(stale)).to be(true)
    end

    it "leaves other price types and other variants alone" do
      base = first.default_price
      wholesale = first.prices.create!(amount: 70, currency: currency, price_type: wholesale_type)
      other_variant = second.prices.create!(amount: 80, currency: currency, price_type: sale, valid_from: 1.week.ago)

      post_batch(prices: [{variant_id: first.id, amount: "35.00", price_type_code: "sale"}], mode: "replace")

      expect(discarded?(stale)).to be(true)
      expect(discarded?(base)).to be(false)
      expect(discarded?(wholesale)).to be(false)
      expect(discarded?(other_variant)).to be(false)
    end

    it "keeps a row the payload did send" do
      post_batch(
        prices: [
          {variant_id: first.id, amount: "59.00", price_type_code: "sale", valid_from: window_start.iso8601},
          {variant_id: first.id, amount: "35.00", price_type_code: "sale"}
        ],
        mode: "replace"
      )

      expect(body["summary"]).to eq("created" => 1, "updated" => 1)
      expect(discarded?(stale)).to be(false)
      expect(stale.reload.amount).to eq(59)
    end

    it "upsert mode leaves the leftover alone" do
      post_batch(prices: [{variant_id: first.id, amount: "35.00", price_type_code: "sale"}])

      expect(body["summary"]).to eq("created" => 1)
      expect(discarded?(stale)).to be(false)
    end

    it "does not delete anything on a dry run" do
      post_batch(
        prices: [{variant_id: first.id, amount: "35.00", price_type_code: "sale"}],
        mode: "replace",
        dry_run: true
      )

      expect(body["summary"]).to eq("created" => 1, "deleted" => 1)
      expect(discarded?(stale)).to be(false)
    end
  end

  def sale = SolidusAdvancedPricing::PriceType.find_by!(code: "sale")

  def wholesale_type = SolidusAdvancedPricing::PriceType.find_by!(code: "wholesale")
end
