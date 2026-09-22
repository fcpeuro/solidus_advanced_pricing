# frozen_string_literal: true

module SolidusAdvancedPricing
  # Discarding a type hides it from admin dropdowns but leaves historical
  # prices resolvable through it; prices are never reassigned when a type is
  # retired, so a retired type's code stays reserved rather than reusable.
  # `::Spree::Base` etc. are qualified from the root: the
  # `solidus_advanced_pricing/spree` decorator namespace shadows the bare
  # `Spree` constant here otherwise (Zeitwerk const-shadowing gotcha).
  class PriceType < ::Spree::Base
    include ::Spree::SoftDeletable

    self.table_name = "solidus_advanced_pricing_price_types"

    # Needed for the solidus_admin index search box (name_or_code_cont); Ransack
    # denies any attribute not explicitly allowed here.
    self.allowed_ransackable_attributes = %w[name code]

    has_many :prices,
      class_name: "::Spree::Price",
      foreign_key: :price_type_id,
      inverse_of: :price_type

    # Not `dependent: :restrict_with_error` — that check is default-scoped and
    # misses discarded prices, which then trip the FK on DELETE.
    before_destroy :prevent_destroying_referenced_type

    before_validation :normalize_code
    before_save :ensure_default_exists_and_is_unique
    before_discard :prevent_discarding_default

    validates :name, presence: true
    # Codes are normalized to lowercase so a plain unique index IS the rule on
    # PostgreSQL, MySQL and SQLite alike. `case_sensitive: false` would have the
    # validator and the index disagree on PG/SQLite, letting `insert_all` create
    # two rows differing only in case.
    validates :code, presence: true, uniqueness: {case_sensitive: true}

    scope :ordered, -> { order(:position, :id) }

    SEEDS = [
      {code: "default", name: "Default", position: 1, default: true},
      {code: "wholesale", name: "Wholesale", position: 2, default: false},
      {code: "sale", name: "Sale", position: 3, default: false},
      {code: "clearance", name: "Clearance", position: 4, default: false},
      {code: "employee", name: "Employee", position: 5, default: false}
    ].freeze

    # Idempotent. Used by the test suite and available to stores for re-seeding.
    # The migration deliberately does NOT call this — a historical migration must
    # not depend on current app code — so the two lists may drift, which is fine:
    # the migration is history, this is the present.
    def self.seed!
      SEEDS.each do |attrs|
        with_discarded.find_or_create_by!(code: attrs[:code]) do |price_type|
          price_type.name = attrs[:name]
          price_type.position = attrs[:position]
          price_type.default = attrs[:default]
        end
      end
    end

    def self.default
      find_by(default: true)
    end

    def to_s
      name
    end

    after_commit { SolidusAdvancedPricing::PriceTypeCache.clear }

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

    def prevent_discarding_default
      return unless default?

      errors.add(:base, :cannot_discard_default)
      throw :abort
    end

    def prevent_destroying_referenced_type
      return unless prices.with_discarded.exists?

      errors.add(:base, :referenced_by_prices)
      throw :abort
    end
  end
end
