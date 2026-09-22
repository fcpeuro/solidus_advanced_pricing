# frozen_string_literal: true

class AddAdvancedPricingToSpreePrices < ActiveRecord::Migration[7.0]
  def change
    add_column :spree_prices, :price_type_id, :bigint
    add_column :spree_prices, :role_id, :bigint
    add_column :spree_prices, :valid_from, :datetime
    add_column :spree_prices, :valid_to, :datetime
    add_column :spree_prices, :admin_notes, :text

    add_index :spree_prices, :price_type_id
    add_index :spree_prices, :role_id
    add_index :spree_prices,
      [:variant_id, :currency, :country_iso, :role_id, :valid_from, :valid_to],
      name: "index_spree_prices_on_advanced_pricing_lookup"

    add_foreign_key :spree_prices, :solidus_advanced_pricing_price_types, column: :price_type_id
    add_foreign_key :spree_prices, :spree_roles, column: :role_id
  end
end
