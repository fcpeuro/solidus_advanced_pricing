# frozen_string_literal: true

class BackfillPriceTypeOnSpreePrices < ActiveRecord::Migration[7.0]
  def up
    default_id = select_value(<<~SQL.squish)
      SELECT id FROM solidus_advanced_pricing_price_types WHERE code = 'default' LIMIT 1
    SQL

    raise "No default price type found; run the seed migration first." if default_id.nil?

    execute <<~SQL.squish
      UPDATE spree_prices SET price_type_id = #{default_id.to_i} WHERE price_type_id IS NULL
    SQL

    change_column_null :spree_prices, :price_type_id, false
  end

  def down
    change_column_null :spree_prices, :price_type_id, true
  end
end
