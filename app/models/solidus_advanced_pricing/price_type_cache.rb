# frozen_string_literal: true

module SolidusAdvancedPricing
  # Process-local memoization for values read on every pricing lookup.
  # Cleared by PriceType's after_save/after_destroy/after_discard callbacks
  # and, later, by Spree::Price.
  module PriceTypeCache
    class << self
      def pricing_role_ids
        return @pricing_role_ids if defined?(@pricing_role_ids)

        @pricing_role_ids = ::Spree::Price.distinct.pluck(:role_id).compact
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

      def clear
        remove_instance_variable(:@pricing_role_ids) if defined?(@pricing_role_ids)
        remove_instance_variable(:@positions) if defined?(@positions)
        remove_instance_variable(:@ids_by_code) if defined?(@ids_by_code)
      end
    end
  end
end
