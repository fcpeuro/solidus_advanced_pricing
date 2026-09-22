# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module PriceDecorator
      def self.prepended(base)
        # with_discarded: a price keeps its type after an admin retires it.
        base.belongs_to :price_type,
          -> { with_discarded },
          class_name: "SolidusAdvancedPricing::PriceType",
          inverse_of: :prices

        base.belongs_to :role,
          class_name: "::Spree::Role",
          optional: true

        base.before_validation :assign_default_price_type
        base.validate :valid_to_after_valid_from
      end

      private

      def assign_default_price_type
        self.price_type_id ||= SolidusAdvancedPricing::PriceTypeCache.default_id
      end

      def valid_to_after_valid_from
        return if valid_from.blank? || valid_to.blank?
        return if valid_to > valid_from

        errors.add(:valid_to, :must_be_after_valid_from)
      end

      ::Spree::Price.prepend self
    end
  end
end
