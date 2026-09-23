# frozen_string_literal: true

module SolidusAdvancedPricing
  # Process-local memoization for values read on every pricing lookup.
  # Cleared by PriceType's after_save/after_destroy/after_discard callbacks
  # and, later, by Spree::Price.
  module PriceTypeCache
    class << self
      # Union with type-level defaults: a role that appears only on a price type
      # (never directly on a price) must still narrow in, or a customer holding
      # only that role would be filtered out before selection ever runs.
      def pricing_role_ids
        return @pricing_role_ids if defined?(@pricing_role_ids)

        @pricing_role_ids = (
          ::Spree::Price.distinct.pluck(:role_id) + PriceType.with_discarded.distinct.pluck(:role_id)
        ).compact.uniq
      end

      # id => position, for the selector's tie-breaker. A handful of rows that
      # change almost never, so one memoized map beats a query per candidate price.
      def positions
        return @positions if defined?(@positions)

        @positions = PriceType.with_discarded.pluck(:id, :position).to_h
      end

      def position_for(price_type_id)
        positions.fetch(price_type_id, 0)
      end

      # code => id. Handful of rows that change almost never.
      def ids_by_code
        return @ids_by_code if defined?(@ids_by_code)

        @ids_by_code = PriceType.with_discarded.pluck(:code, :id).to_h
      end

      def id_for(code)
        ids_by_code[code.to_s]
      end

      # id => role_id, for the effective-role fallback. with_discarded matters —
      # a retired type's default role must still apply to historical prices.
      def role_ids
        return @role_ids if defined?(@role_ids)

        @role_ids = PriceType.with_discarded.pluck(:id, :role_id).to_h
      end

      def role_id_for(price_type_id)
        role_ids[price_type_id]
      end

      def clear
        remove_instance_variable(:@pricing_role_ids) if defined?(@pricing_role_ids)
        remove_instance_variable(:@positions) if defined?(@positions)
        remove_instance_variable(:@ids_by_code) if defined?(@ids_by_code)
        remove_instance_variable(:@role_ids) if defined?(@role_ids)
      end
    end
  end
end
