# frozen_string_literal: true

class CreateSolidusAdvancedPricingPriceBatchRuns < ActiveRecord::Migration[7.0]
  def change
    # A submitted payload can run to megabytes. MySQL's TEXT is 64KB and
    # truncates silently past it, so ask for LONGTEXT there; other adapters
    # have no such ceiling and reject the limit, hence the conditional.
    long_text = connection.adapter_name.match?(/mysql/i) ? 4_294_967_295 : nil

    create_table :solidus_advanced_pricing_price_batch_runs do |t|
      t.string :status, null: false, default: "queued"
      t.string :mode, null: false, default: "upsert"
      t.boolean :dry_run, null: false, default: false
      t.integer :total_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.text :payload, limit: long_text, null: false
      t.text :report, limit: long_text
      t.text :failure_reason
      t.integer :user_id
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :solidus_advanced_pricing_price_batch_runs, :status
    add_index :solidus_advanced_pricing_price_batch_runs, :created_at
  end
end
