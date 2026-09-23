# frozen_string_literal: true

class SeedSolidusAdvancedPricingPriceTypes < ActiveRecord::Migration[7.0]
  SEEDS = [
    {code: "wholesale", name: "Wholesale", position: 1},
    {code: "sale", name: "Sale", position: 2},
    {code: "clearance", name: "Clearance", position: 3},
    {code: "employee", name: "Employee", position: 4},
    {code: "map", name: "MAP", position: 5},
    {code: "promotional", name: "Promotional", position: 6}
  ].freeze

  def up
    now = Time.current

    SEEDS.each do |attrs|
      next if price_types.where(code: attrs[:code]).exists?

      price_types.insert_all([attrs.merge(created_at: now, updated_at: now)])
    end
  end

  def down
    price_types.where(code: SEEDS.map { |attrs| attrs[:code] }).delete_all
  end

  private

  def price_types
    @price_types ||= Class.new(ActiveRecord::Base) do
      self.table_name = "solidus_advanced_pricing_price_types"
    end
  end
end
