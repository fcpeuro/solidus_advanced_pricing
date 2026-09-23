# frozen_string_literal: true

module Spree
  module Api
    class PriceTypesController < Spree::Api::BaseController
      # Retired types are excluded: this endpoint exists so a client can build a
      # valid price payload, and a discarded type is no longer a valid choice.
      # Historical prices still serialize their own type's code via the prices
      # endpoint, so nothing is hidden from a reader.
      def index
        authorize! :index, SolidusAdvancedPricing::PriceType
        @price_types = SolidusAdvancedPricing::PriceType.accessible_by(current_ability, :index).ordered
        respond_with(@price_types)
      end
    end
  end
end
