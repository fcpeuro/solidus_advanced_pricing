# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Async Price Batch API" do
  include ActiveJob::TestHelper

  # See prices_spec.rb: `spree_roles <<` never generates the key on its own.
  let(:admin) { create(:admin_user).tap(&:generate_spree_api_key!) }
  let(:customer) { create(:user).tap(&:generate_spree_api_key!) }
  let!(:variant) { create(:variant, price: 100) }
  let(:sale) { SolidusAdvancedPricing::PriceType.find_by!(code: "sale") }

  # See price_batches_spec.rb: form encoding cannot carry heterogeneous rows.
  def post_run(prices:, user: admin, **options)
    post "/api/price_batches",
      params: {prices: prices}.merge(options),
      headers: {"Authorization" => "Bearer #{user.spree_api_key}"},
      as: :json
  end

  def get_run(id, user: admin)
    get "/api/price_batches/#{id}", headers: {"Authorization" => "Bearer #{user.spree_api_key}"}
  end

  def body = JSON.parse(response.body)

  describe "POST /api/price_batches" do
    it "accepts the payload and enqueues it" do
      expect {
        post_run(prices: [{variant_id: variant.id, amount: "35.00", price_type_code: "sale"}])
      }.to have_enqueued_job(SolidusAdvancedPricing::PriceBatchJob)

      expect(response).to have_http_status(:accepted)
      expect(body["status"]).to eq("queued")
      expect(body["total_rows"]).to eq(1)
    end

    it "does not apply anything before the job runs" do
      post_run(prices: [{variant_id: variant.id, amount: "35.00", price_type_code: "sale"}])

      expect(variant.prices.kept.count).to eq(1)
    end

    it "records who submitted it" do
      post_run(prices: [{variant_id: variant.id, amount: "35.00"}])

      expect(SolidusAdvancedPricing::PriceBatchRun.last.user_id).to eq(admin.id)
    end

    it "refuses a payload over the async row limit" do
      allow(SolidusAdvancedPricing.config).to receive(:async_batch_row_limit).and_return(2)

      expect {
        post_run(prices: Array.new(3) { {variant_id: variant.id, amount: "1.00"} })
      }.not_to have_enqueued_job(SolidusAdvancedPricing::PriceBatchJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["error"]).to include("limited to 2 rows")
    end

    it "refuses an unknown mode" do
      post_run(prices: [{variant_id: variant.id, amount: "1.00"}], mode: "obliterate")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(SolidusAdvancedPricing::PriceBatchRun.count).to eq(0)
    end

    it "refuses a non-admin" do
      post_run(prices: [{variant_id: variant.id, amount: "1.00"}], user: customer)

      expect(response).to have_http_status(:unauthorized)
      expect(SolidusAdvancedPricing::PriceBatchRun.count).to eq(0)
    end
  end

  describe "GET /api/price_batches/:id" do
    it "reports progress while queued and the outcome once run" do
      post_run(prices: [{variant_id: variant.id, amount: "35.00", price_type_code: "sale"}])
      run_id = body["id"]

      get_run(run_id)
      expect(body["status"]).to eq("queued")
      expect(body).not_to have_key("summary")

      perform_enqueued_jobs

      get_run(run_id)
      expect(body["status"]).to eq("completed")
      expect(body["summary"]).to eq("created" => 1)
      expect(body["processed_rows"]).to eq(1)
      expect(variant.prices.kept.count).to eq(2)
    end

    it "reports only the rows worth acting on" do
      post_run(prices: [
        {variant_id: variant.id, amount: "35.00", price_type_code: "sale"},
        {variant_id: 0, amount: "30.00"}
      ])
      run_id = body["id"]
      perform_enqueued_jobs

      get_run(run_id)
      expect(body["summary"]).to eq("created" => 1, "error" => 1)
      expect(body["results"].map { |r| r["status"] }).to eq(["error"])
      expect(body["results_truncated"]).to be(false)
    end

    it "refuses a non-admin" do
      post_run(prices: [{variant_id: variant.id, amount: "1.00"}])
      get_run(body["id"], user: customer)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "slicing" do
    before { allow(SolidusAdvancedPricing.config).to receive(:batch_slice_size).and_return(1) }

    it "applies every row across slices and reports absolute row indexes" do
      other = create(:variant, price: 200)

      post_run(prices: [
        {variant_id: variant.id, amount: "35.00", price_type_code: "sale"},
        {variant_id: other.id, amount: "45.00", price_type_code: "sale"},
        {variant_id: 0, amount: "1.00"}
      ])
      run_id = body["id"]
      perform_enqueued_jobs

      get_run(run_id)
      expect(body["summary"]).to eq("created" => 2, "error" => 1)
      # Index 2, not 0: the third row was the only one in its slice.
      expect(body["results"].first["index"]).to eq(2)
      expect(body["processed_rows"]).to eq(3)
    end

    it "still catches a duplicate whose twin landed in an earlier slice" do
      row = {variant_id: variant.id, amount: "35.00", price_type_code: "sale"}
      post_run(prices: [row, row])
      run_id = body["id"]
      perform_enqueued_jobs

      get_run(run_id)
      expect(body["summary"]).to eq("created" => 1, "error" => 1)
      expect(body["results"].first["errors"].first).to include("duplicate of row 0")
    end

    it "defers replace deletion until every slice has landed" do
      first_window = variant.prices.create!(amount: 60, currency: variant.default_price.currency,
        price_type: sale, valid_from: 2.weeks.ago.change(usec: 0))
      second_window = variant.prices.create!(amount: 70, currency: variant.default_price.currency,
        price_type: sale, valid_from: 1.week.ago.change(usec: 0))

      post_run(
        prices: [
          {variant_id: variant.id, amount: "61.00", price_type_code: "sale", valid_from: first_window.valid_from.iso8601},
          {variant_id: variant.id, amount: "71.00", price_type_code: "sale", valid_from: second_window.valid_from.iso8601}
        ],
        mode: "replace"
      )
      perform_enqueued_jobs

      # Deleting per slice would have discarded second_window while processing
      # slice 0, then re-created it in slice 1 under a new id.
      expect(Spree::Price.with_discarded.find(second_window.id).deleted_at).to be_nil
      expect(second_window.reload.amount).to eq(71)
      expect(Spree::Price.with_discarded.find(first_window.id).deleted_at).to be_nil
    end

    it "discards a leftover once, after the last slice" do
      leftover = variant.prices.create!(amount: 60, currency: variant.default_price.currency,
        price_type: sale, valid_from: 2.weeks.ago.change(usec: 0))

      post_run(prices: [{variant_id: variant.id, amount: "35.00", price_type_code: "sale"}], mode: "replace")
      run_id = body["id"]
      perform_enqueued_jobs

      get_run(run_id)
      expect(body["summary"]).to eq("created" => 1, "deleted" => 1)
      expect(Spree::Price.with_discarded.find(leftover.id).deleted_at).to be_present
    end
  end

  describe "dry_run" do
    it "reports what it would do and writes nothing" do
      post_run(prices: [{variant_id: variant.id, amount: "35.00", price_type_code: "sale"}], dry_run: true)
      run_id = body["id"]
      perform_enqueued_jobs

      get_run(run_id)
      expect(body["dry_run"]).to be(true)
      expect(body["summary"]).to eq("created" => 1)
      expect(variant.prices.kept.count).to eq(1)
    end

    it "does not discard anything in replace mode" do
      leftover = variant.prices.create!(amount: 60, currency: variant.default_price.currency,
        price_type: sale, valid_from: 2.weeks.ago.change(usec: 0))

      post_run(
        prices: [{variant_id: variant.id, amount: "35.00", price_type_code: "sale"}],
        mode: "replace",
        dry_run: true
      )
      perform_enqueued_jobs

      expect(leftover.reload.deleted_at).to be_nil
    end
  end

  describe "when the run dies partway" do
    before { allow(SolidusAdvancedPricing.config).to receive(:batch_slice_size).and_return(1) }

    it "marks the run failed, keeps the report, and leaves committed slices in place" do
      other = create(:variant, price: 200)
      calls = 0
      allow(SolidusAdvancedPricing::PriceBatch).to receive(:new).and_wrap_original do |original, **args|
        calls += 1
        raise "boom" if calls == 2

        original.call(**args)
      end

      post_run(prices: [
        {variant_id: variant.id, amount: "35.00", price_type_code: "sale"},
        {variant_id: other.id, amount: "45.00", price_type_code: "sale"}
      ])
      run_id = body["id"]

      expect { perform_enqueued_jobs }.to raise_error(/boom/)

      get_run(run_id)
      expect(body["status"]).to eq("failed")
      expect(body["failure_reason"]).to include("boom")
      expect(body["summary"]).to eq("created" => 1)
      # Not rolled back: slicing trades atomicity for size, and this is the cost.
      expect(variant.prices.kept.count).to eq(2)
      expect(other.prices.kept.count).to eq(1)
    end
  end
end
