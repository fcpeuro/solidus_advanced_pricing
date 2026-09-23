# frozen_string_literal: true

module Spree
  module Api
    class PriceBatchRunsController < Spree::Api::BaseController
      def create
        authorize! :create, Spree::Price

        rows = batch_rows
        limit = SolidusAdvancedPricing.config.async_batch_row_limit

        if rows.size > limit
          return render json: {error: "batch is limited to #{limit} rows, got #{rows.size}"},
            status: :unprocessable_entity
        end

        unless SolidusAdvancedPricing::PriceBatch::MODES.include?(params.fetch(:mode, "upsert").to_s)
          return render json: {error: "mode must be one of #{SolidusAdvancedPricing::PriceBatch::MODES.join(", ")}"},
            status: :unprocessable_entity
        end

        @run = SolidusAdvancedPricing::PriceBatchRun.new(
          mode: params.fetch(:mode, "upsert"),
          dry_run: ActiveModel::Type::Boolean.new.cast(params[:dry_run]) || false,
          user: current_api_user
        )
        @run.rows = rows

        if @run.save
          SolidusAdvancedPricing::PriceBatchJob.perform_later(@run.id)
          render :show, status: :accepted
        else
          invalid_resource!(@run)
        end
      end

      def show
        authorize! :show, Spree::Price
        @run = SolidusAdvancedPricing::PriceBatchRun.find(params[:id])
        render :show
      end

      private

      def batch_rows
        params.require(:prices).map do |row|
          row.permit(
            *Spree::PermittedAttributes.price_attributes,
            :id,
            :variant_id,
            :sku,
            :price_type_code
          ).to_h
        end
      end
    end
  end
end
