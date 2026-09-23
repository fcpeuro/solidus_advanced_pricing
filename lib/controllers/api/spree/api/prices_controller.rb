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

      def create
        authorize! :create, Spree::Price

        @price = variant.prices.new(currency: Spree::Config.default_pricing_options.currency)
        assign_price_attributes(@price)

        if @price.errors.empty? && @price.save
          render :show, status: :created
        else
          invalid_resource!(@price)
        end
      end

      def update
        # `find` then `authorize!`, rather than an accessible_by scope, so a
        # caller without rights gets 401 like every other action here instead of
        # a 404 that reads as "no such price".
        @price = live_prices.find(params[:id])
        authorize! :update, @price

        assign_price_attributes(@price)

        if @price.errors.empty? && @price.save
          render :show
        else
          invalid_resource!(@price)
        end
      end

      # Soft delete: `discard`, not `destroy`, so the row stays available to
      # anything reporting on what a variant used to cost.
      def destroy
        @price = live_prices.find(params[:id])
        authorize! :destroy, @price

        @price.discard
        render plain: nil, status: :no_content
      end

      private

      # Lists what exists for this variant; never routed through
      # current_pricing_options, which would filter by the requesting admin's
      # own roles via current_spree_user.
      #
      # `Spree::Variant#prices` is declared `-> { with_discarded }` in core, so
      # the default here has to put `kept` back -- otherwise every listing
      # includes prices someone deleted. `?show_deleted=true` opts back in, the
      # same switch core uses on products.
      def scope
        prices = variant.prices.accessible_by(current_ability, :index)
        params[:show_deleted] ? prices : prices.kept
      end

      # Writes never reach a discarded price: undeleting is not an API operation,
      # and silently editing a deleted row is worse than a 404.
      def live_prices
        variant.prices.kept
      end

      def variant
        @variant ||= Spree::Variant.find(params[:variant_id])
      end

      # `price_type_code` is accepted as an alternative to `price_type_id` because
      # ids are per-database and codes are not -- a payload written against staging
      # has to work unchanged against production. An explicit null means the untyped
      # base price, so a present-but-empty key is meaningful and not the same as an
      # absent one.
      def assign_price_attributes(price)
        attributes = params.require(:price).permit(*Spree::PermittedAttributes.price_attributes, :price_type_code)

        if attributes.key?("price_type_code")
          code = attributes.delete("price_type_code")

          if attributes.key?("price_type_id")
            price.errors.add(:price_type_id, :ambiguous_price_type)
            return
          end

          begin
            attributes["price_type_id"] = code.presence && SolidusAdvancedPricing.resolve_price_type_id(code)
          rescue ArgumentError
            price.errors.add(:price_type_id, :unknown_code, code: code)
            return
          end
        end

        price.assign_attributes(attributes)
      end
    end
  end
end
