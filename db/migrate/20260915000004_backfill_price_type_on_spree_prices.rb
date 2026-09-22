# frozen_string_literal: true

class BackfillPriceTypeOnSpreePrices < ActiveRecord::Migration[7.0]
  def up
    default_id = select_value(<<~SQL.squish)
      SELECT id FROM solidus_advanced_pricing_price_types
      WHERE #{quote_column_name("default")} = #{quoted_true} LIMIT 1
    SQL

    default_id ||= select_value(<<~SQL.squish)
      SELECT id FROM solidus_advanced_pricing_price_types WHERE code = 'default' LIMIT 1
    SQL

    raise "No default price type found; run the seed migration first." if default_id.nil?

    backfill_sql = <<~SQL.squish
      UPDATE spree_prices SET price_type_id = #{default_id.to_i} WHERE price_type_id IS NULL
    SQL

    execute backfill_sql
    # Re-sweep: the UPDATE only row-locks, so a concurrent insert can slip a NULL
    # past the first pass and abort SET NOT NULL mid-deploy on PostgreSQL.
    execute backfill_sql

    change_column_null :spree_prices, :price_type_id, false
  end

  def down
    change_column_null :spree_prices, :price_type_id, true
  end
end
