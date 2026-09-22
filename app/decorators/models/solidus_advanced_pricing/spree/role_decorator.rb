# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module RoleDecorator
      def self.prepended(base)
        # No re-run guard needed: unlike belongs_to, a symbol-filtered callback
        # dedupes on re-registration, so this is already safe under to_prepare reloads.
        base.before_destroy :prevent_destroying_referenced_role
      end

      private

      def prevent_destroying_referenced_role
        return unless ::Spree::Price.with_discarded.exists?(role_id: id)

        errors.add(:base, :referenced_by_prices)
        throw :abort
      end

      ::Spree::Role.prepend self
    end
  end
end
