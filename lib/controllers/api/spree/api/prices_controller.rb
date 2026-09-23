# frozen_string_literal: true

module Spree
  module Api
    class PricesController < Spree::Api::BaseController
      def index
        authorize! :index, Spree::Price
        @prices = scope.order(:id)
        respond_with(@prices)
      end

      def show
        @price = scope.find(params[:id])
        authorize! :show, @price
        respond_with(@price)
      end

      private

      # Lists what exists for this variant; never routed through
      # current_pricing_options, which would filter by the requesting admin's
      # own roles via current_spree_user.
      def scope
        variant.prices.accessible_by(current_ability, :index)
      end

      def variant
        @variant ||= Spree::Variant.find(params[:variant_id])
      end
    end
  end
end
