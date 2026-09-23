# frozen_string_literal: true

module Spree
  module Api
    class PriceBatchesController < Spree::Api::BaseController
      rescue_from SolidusAdvancedPricing::PriceBatch::TooManyRows, with: :batch_too_large
      rescue_from SolidusAdvancedPricing::PriceBatch::InvalidMode, with: :bad_mode

      # Always 200 with a per-row report, never a partial 4xx: a caller that
      # sent 500 rows and got a bare 422 has no way to know which of them
      # landed. The 4xx cases here are the ones where no row was even looked at.
      def create
        authorize! :create, Spree::Price

        @batch = SolidusAdvancedPricing::PriceBatch.new(
          rows: batch_rows,
          mode: params.fetch(:mode, "upsert"),
          dry_run: params[:dry_run]
        ).call

        render :create, status: :ok
      end

      private

      def batch_rows
        params.require(:prices).map do |row|
          row.permit(
            *Spree::PermittedAttributes.price_attributes,
            :variant_id,
            :sku,
            :price_type_code
          )
        end
      end

      def batch_too_large(exception)
        render json: {error: exception.message}, status: :unprocessable_entity
      end

      def bad_mode(exception)
        render json: {error: exception.message}, status: :unprocessable_entity
      end
    end
  end
end
