# frozen_string_literal: true

module SolidusAdvancedPricing
  class PriceType < Spree::Base
    include Spree::SoftDeletable

    self.table_name = 'solidus_advanced_pricing_price_types'

    has_many :prices,
      class_name: 'Spree::Price',
      foreign_key: :price_type_id,
      inverse_of: :price_type,
      dependent: :restrict_with_error

    validates :name, presence: true
    validates :code, presence: true, uniqueness: { case_sensitive: false }

    scope :ordered, -> { order(:position, :id) }

    def self.default
      find_by(default: true)
    end

    def to_s
      name
    end
  end
end
