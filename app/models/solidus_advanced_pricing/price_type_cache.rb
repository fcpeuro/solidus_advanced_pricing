# frozen_string_literal: true

module SolidusAdvancedPricing
  # Process-local memoization for values read on every pricing lookup.
  # Cleared by PriceType's after_save/after_destroy/after_discard callbacks
  # and, later, by Spree::Price.
  module PriceTypeCache
    class << self
      # `defined?` rather than `||=`: before seeding, the default id is
      # legitimately nil, and `||=` would re-query on every single pricing
      # lookup — the exact hot path this exists to avoid.
      def default_id
        return @default_id if defined?(@default_id)

        @default_id = PriceType.with_discarded.find_by(default: true)&.id
      end

      def pricing_role_ids
        return @pricing_role_ids if defined?(@pricing_role_ids)

        @pricing_role_ids = ::Spree::Price.distinct.pluck(:role_id).compact
      end

      def clear
        remove_instance_variable(:@default_id) if defined?(@default_id)
        remove_instance_variable(:@pricing_role_ids) if defined?(@pricing_role_ids)
      end
    end
  end
end
