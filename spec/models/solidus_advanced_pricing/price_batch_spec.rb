# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PriceBatch do
  let!(:variant) { create(:variant, price: 100) }
  let(:currency) { Spree::Config.default_pricing_options.currency }
  let(:sale) { SolidusAdvancedPricing::PriceType.find_by!(code: "sale") }

  def row(overrides = {})
    {variant_id: variant.id, amount: "35.00", price_type_id: sale.id}.merge(overrides)
  end

  describe "the batch_guard hook" do
    after { SolidusAdvancedPricing.config.batch_guard = nil }

    it "sees every row already written" do
      seen = nil
      SolidusAdvancedPricing.config.batch_guard = ->(batch) { seen = batch.summary }

      described_class.new(rows: [row]).call

      expect(seen).to eq(created: 1)
    end

    it "aborts the whole batch when it raises" do
      stop = Class.new(StandardError)
      SolidusAdvancedPricing.config.batch_guard = ->(_batch) { raise stop }

      expect {
        described_class.new(rows: [row, row(amount: "30.00", valid_from: 1.day.from_now)]).call
      }.to raise_error(stop)

      expect(variant.prices.kept.where(price_type_id: sale.id)).to be_empty
    end

    it "rolls back rows written before a guard that raises" do
      SolidusAdvancedPricing.config.batch_guard = ->(_batch) { raise "no" }

      suppress(RuntimeError) { described_class.new(rows: [row]).call }

      expect(variant.prices.kept.count).to eq(1)
    end
  end

  describe "argument checking" do
    it "refuses a mode it does not implement" do
      expect { described_class.new(rows: [], mode: "obliterate") }
        .to raise_error(described_class::InvalidMode, /upsert/)
    end

    it "refuses a payload over the configured row limit" do
      expect { described_class.new(rows: [row, row, row], row_limit: 2) }
        .to raise_error(described_class::TooManyRows, /limited to 2 rows/)
    end

    it "defaults the row limit to the extension configuration" do
      expect(described_class.new(rows: []).instance_variable_get(:@row_limit))
        .to eq(SolidusAdvancedPricing.config.batch_row_limit)
    end
  end

  describe "#summary" do
    it "counts each outcome" do
      described_class.new(rows: [row]).call

      batch = described_class.new(rows: [
        row,
        row(amount: "30.00", valid_from: 1.day.from_now),
        row(price_type_id: nil, variant_id: 0)
      ]).call

      expect(batch.summary).to eq(unchanged: 1, created: 1, error: 1)
    end
  end
end
