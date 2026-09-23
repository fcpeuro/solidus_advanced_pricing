# frozen_string_literal: true

module Spree
  module Admin
    class PriceTypesController < ResourceController
      private

      def model_class
        SolidusAdvancedPricing::PriceType
      end

      def collection
        @collection ||= model_class.ordered
      end

      def permitted_resource_params
        params.require(:price_type).permit(:name, :code, :position, :role_id)
      end

      # ResourceController derives these from model_class.model_name, which for a
      # namespaced model produces route names (e.g. admin_solidus_advanced_pricing_price_types)
      # that don't match the admin_price_types routes actually declared.
      def new_object_url(options = {})
        spree.new_admin_price_type_url(options)
      end

      def edit_object_url(object, options = {})
        spree.edit_admin_price_type_url(object, options)
      end

      def object_url(object = @object, options = {})
        spree.admin_price_type_url(object, options)
      end

      def collection_url(options = {})
        spree.admin_price_types_url(options)
      end
    end
  end
end
