# frozen_string_literal: true

module SolidusAdvancedPricing
  # Discarding a type hides it from admin dropdowns but leaves historical
  # prices resolvable through it; prices are never reassigned when a type is
  # retired, so a retired type's code stays reserved rather than reusable.
  class PriceType < Spree::Base
    include Spree::SoftDeletable

    self.table_name = 'solidus_advanced_pricing_price_types'

    # NOTE: `has_many :prices` is deliberately NOT declared here. `spree_prices`
    # has no `price_type_id` column and `Spree::Price` has no `price_type`
    # association until Task 7, so declaring it now makes both `prices` and
    # `destroy` raise InverseOfAssociationNotFoundError. It lands in Task 7.

    before_validation :normalize_code
    before_save :ensure_default_exists_and_is_unique

    validates :name, presence: true
    # Codes are normalized to lowercase so a plain unique index IS the rule on
    # PostgreSQL, MySQL and SQLite alike. `case_sensitive: false` would have the
    # validator and the index disagree on PG/SQLite, letting `insert_all` create
    # two rows differing only in case.
    validates :code, presence: true, uniqueness: { case_sensitive: true }

    scope :ordered, -> { order(:position, :id) }

    def self.default
      find_by(default: true)
    end

    def to_s
      name
    end

    private

    def normalize_code
      self.code = code&.strip&.downcase.presence
    end

    # Mirrors Spree::Store#ensure_default_exists_and_is_unique. Without it two
    # rows can carry `default: true`, and a later task memoizes the default id
    # per process — two workers could memoize different ids and price lookups
    # would diverge by worker.
    def ensure_default_exists_and_is_unique
      if default?
        self.class.where.not(id: id).update_all(default: false)
      elsif self.class.where(default: true).where.not(id: id).none?
        self.default = true
      end
    end
  end
end
