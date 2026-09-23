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

    belongs_to :role, class_name: "::Spree::Role", optional: true

    # Not `dependent: :restrict_with_error` — that check is default-scoped and
    # misses discarded prices, which then trip the FK on DELETE.
    before_destroy :prevent_destroying_referenced_type

    before_validation :normalize_code

    validates :name, presence: true
    # Codes are normalized to lowercase so a plain unique index IS the rule on
    # PostgreSQL, MySQL and SQLite alike. `case_sensitive: false` would have the
    # validator and the index disagree on PG/SQLite, letting `insert_all` create
    # two rows differing only in case.
    validates :code, presence: true, uniqueness: {case_sensitive: true}

    scope :ordered, -> { order(:position, :id) }

    SEEDS = [
      {code: "wholesale", name: "Wholesale", position: 1},
      {code: "sale", name: "Sale", position: 2},
      {code: "clearance", name: "Clearance", position: 3},
      {code: "employee", name: "Employee", position: 4},
      {code: "map", name: "MAP", position: 5},
      {code: "promotional", name: "Promotional", position: 6}
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
        end
      end
    end

    def to_s
      name
    end

    after_commit { SolidusAdvancedPricing::PriceTypeCache.clear }

    private

    def normalize_code
      self.code = code&.strip&.downcase.presence
    end

    def prevent_destroying_referenced_type
      return unless prices.with_discarded.exists?

      errors.add(:base, :referenced_by_prices)
      throw :abort
    end
  end
end
