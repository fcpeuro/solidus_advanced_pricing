# frozen_string_literal: true

class CreateSolidusAdvancedPricingPriceTypes < ActiveRecord::Migration[7.0]
  def change
    create_table :solidus_advanced_pricing_price_types do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.integer :position, null: false, default: 0
      t.boolean :default, null: false, default: false
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :solidus_advanced_pricing_price_types, :code, unique: true
    add_index :solidus_advanced_pricing_price_types, :deleted_at
  end
end
