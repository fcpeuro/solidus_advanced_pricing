# frozen_string_literal: true

class AddRoleToSolidusAdvancedPricingPriceTypes < ActiveRecord::Migration[7.0]
  def change
    # :integer, not :bigint — spree_roles.id is int and MySQL rejects mismatched FK precision.
    add_column :solidus_advanced_pricing_price_types, :role_id, :integer
    add_index :solidus_advanced_pricing_price_types, :role_id
    add_foreign_key :solidus_advanced_pricing_price_types, :spree_roles, column: :role_id, on_delete: :restrict
  end
end
