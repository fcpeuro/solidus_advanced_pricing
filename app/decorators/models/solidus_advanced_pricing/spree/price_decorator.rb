# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module PriceDecorator
      def self.prepended(base)
        # solidus_support reloads decorators via bare `load` on every to_prepare;
        # re-running this method would redefine the association and its
        # callbacks (valid_to_after_valid_from, after_commit) each time.
        return if base.reflect_on_association(:price_type)

        # with_discarded: a price keeps its type after an admin retires it.
        # optional: true because price_type_id nil is a real value here — the
        # untyped base price — not a validation gap.
        base.belongs_to :price_type,
          -> { with_discarded },
          class_name: "SolidusAdvancedPricing::PriceType",
          inverse_of: :prices,
          optional: true

        base.belongs_to :role,
          class_name: "::Spree::Role",
          optional: true

        base.validate :valid_to_after_valid_from

        # valid_to is exclusive so a window ending at midnight and the next one starting at midnight do not both match.
        base.scope :valid_at, ->(time) {
          where(arel_table[:valid_from].eq(nil).or(arel_table[:valid_from].lteq(time)))
            .where(arel_table[:valid_to].eq(nil).or(arel_table[:valid_to].gt(time)))
        }

        # Tests the *effective* role (price's own role_id, falling back to its
        # type's) via COALESCE over a LEFT JOIN, not just the price's column —
        # a price whose type carries a default role must be excluded from a
        # guest's listing even though the price row itself has role_id: nil.
        # left_joins(:price_type) does not apply PriceType's `kept` default
        # scope (verified empirically), so a retired type's default role still
        # applies to its historical prices.
        base.scope :visible_to_roles, ->(role_ids) {
          price_types_table = SolidusAdvancedPricing::PriceType.arel_table
          effective_role_id = Arel::Nodes::NamedFunction.new(
            "COALESCE", [arel_table[:role_id], price_types_table[:role_id]]
          )

          condition = effective_role_id.eq(nil)
          condition = condition.or(effective_role_id.in(role_ids)) if role_ids.present?

          left_joins(:price_type).where(condition)
        }

        base.scope :for_price_type, ->(price_type) {
          where(price_type_id: price_type)
        }

        base.after_commit { SolidusAdvancedPricing::PriceTypeCache.clear }
      end

      # nil on the price means "inherit from the type", not "public".
      def effective_role_id
        role_id || SolidusAdvancedPricing::PriceTypeCache.role_id_for(price_type_id)
      end

      private

      def valid_to_after_valid_from
        return if valid_from.blank? || valid_to.blank?
        return if valid_to > valid_from

        errors.add(:valid_to, :must_be_after_valid_from)
      end

      ::Spree::Price.prepend self
    end
  end
end
