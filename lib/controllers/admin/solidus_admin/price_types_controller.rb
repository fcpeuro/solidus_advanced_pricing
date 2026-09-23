# frozen_string_literal: true

module SolidusAdmin
  class PriceTypesController < SolidusAdmin::ResourcesController
    private

    def resource_class = SolidusAdvancedPricing::PriceType

    def permitted_resource_params
      params.require(:price_type).permit(:name, :code, :position, :role_id)
    end

    # ResourcesController derives these from resource_class.model_name, which for
    # a namespaced model produces "solidus_advanced_pricing_price_type(s)" instead
    # of the "price_type(s)" the admin_resources :price_types route actually
    # declares -- same mismatch already worked around in the legacy backend
    # controller.
    def resource_name = "price_type"

    def plural_resource_name = "price_types"

    # Authorization::authorization_subject infers "Spree::#{controller_name.classify}",
    # which doesn't exist for our namespaced model either.
    def authorization_subject = SolidusAdvancedPricing::PriceType
  end
end
