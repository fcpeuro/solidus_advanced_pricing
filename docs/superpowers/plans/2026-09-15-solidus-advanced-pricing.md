# solidus_advanced_pricing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Solidus extension gem giving `Spree::Price` an admin-managed price type, an optional validity window, optional single-role targeting, and internal admin notes — without monkey-patching price lookup.

**Architecture:** Two subclasses (`PricingOptions`, `PriceSelector`) registered through `Spree::Config.variant_price_selector_class`, which core delegates `pricing_options_class` from. Everything else is additive columns on `spree_prices`, one gem-owned `price_types` table, Deface overrides for the legacy backend, a price-types CRUD for solidus_admin, and an API controller.

**Tech Stack:** Ruby 3.3.10, Rails >= 7.2, Solidus >= 4.0, solidus_dev_support 2.12, solidus_support 0.15, RSpec, FactoryBot, Deface.

**Spec:** `docs/superpowers/specs/2026-09-14-solidus-advanced-pricing-design.md`

## Standing rules for every task

0. **Keep code comments to one or two lines.** A comment names the non-obvious constraint or
   the bug being prevented, then stops. Reproduction steps, arithmetic, alternatives considered
   and verification belong in the commit message, not above the method. Where this plan shows a
   longer comment, trim it and move the detail into the commit body.
0.5. **Always root-qualify Solidus constants as `::Spree::...` inside
   `module SolidusAdvancedPricing`.** The decorator directory
   `app/decorators/models/solidus_advanced_pricing/spree/` makes Zeitwerk define an implicit
   `SolidusAdvancedPricing::Spree` module, so a bare `Spree::Base` resolves to that sibling
   namespace and raises `uninitialized constant SolidusAdvancedPricing::Spree::Base`. This
   applies to every real constant reference; string forms like
   `class_name: "Spree::Price"` are unaffected, because `constantize` resolves from `Object`
   rather than lexical scope.
1. **Run `bundle exec rubocop -a` before every commit, and make sure `bundle exec rubocop`
   reports no offenses.** CI runs `bundle exec rubocop -ESP` on every pull request, so a lint
   failure is a red build. Note that `solidus_dev_support`'s RuboCop config prefers
   **double-quoted** strings, while its generator templates — and the code samples throughout
   this plan — use single quotes. Write the code as given, then let `rubocop -a` normalize it.
   Do not hand-convert and do not edit `.rubocop.yml` to dodge this.
2. **Run the whole suite (`bundle exec rspec`), not just the task's own spec file**, before
   committing. Several tasks change shared behavior — seeded price types, the registered price
   selector, `default_price_attributes` — in ways that surface as failures in earlier specs.
3. **When a task's change breaks an earlier expectation, fix the expectation, not the
   implementation** — unless the failure reveals the implementation is actually wrong, in which
   case stop and escalate rather than deciding alone.
4. **Never weaken an assertion to force green.** If the only way to pass is to assert less,
   that is a signal to escalate.
5. Commit messages take no attribution lines, "Generated with" footers, or Co-Authored-By
   trailers.

**Phases** — each ends with working, tested software:

| Phase | Tasks | Delivers |
|---|---|---|
| 0 Scaffold | 1–2 | Gem skeleton, dummy app, green empty suite |
| 1 PriceType | 3–6 | Model, seeds, guards |
| 2 Price columns | 7–9 | Columns, associations, scopes |
| 3 PricingOptions | 10–12 | Context object + cache key |
| 4 PriceSelector | 13–15 | Selection algorithm |
| 5 Integration | 16–17 | `with_prices`, backward-compat guarantee |
| 6 Legacy admin | 18–20 | Deface overrides, price types CRUD |
| 7 solidus_admin | 21 | Price types CRUD |
| 8 API | 22–23 | Prices endpoint |
| 9 Release prep | 24–25 | Install generator, README |

---

## File Structure

**Always loaded (`app/`)**

- `app/models/solidus_advanced_pricing/price_type.rb` — the type model, its guards, seeds lookup
- `app/models/solidus_advanced_pricing/pricing_options.rb` — customer context (`at`, `customer_role_ids`) + cache key
- `app/models/solidus_advanced_pricing/price_selector.rb` — the selection algorithm
- `app/decorators/models/solidus_advanced_pricing/spree/price_decorator.rb` — associations, scopes, validations
- `app/decorators/models/solidus_advanced_pricing/spree/variant_decorator.rb` — `with_prices` override
- `app/decorators/models/solidus_advanced_pricing/spree/app_configuration_decorator.rb` — cache granularity preference

**Backend-only (`lib/…/backend`, loaded only when `solidus_backend` is present)**

- `lib/controllers/backend/spree/admin/price_types_controller.rb`
- `lib/views/backend/spree/admin/price_types/{index,new,edit,_form}.html.erb`
- `lib/views/backend/spree/admin/prices/_advanced_fields.html.erb`
- `app/overrides/spree/admin/prices/_form/add_advanced_fields.html.erb.deface`

**Admin-only (`lib/…/admin`, loaded only when `solidus_admin` is present)**

- `lib/controllers/admin/solidus_admin/price_types_controller.rb`
- `lib/components/admin/solidus_admin/price_types/index/component.rb` + `.html.erb`

**API-only (`lib/…/api`, loaded only when `solidus_api` is present)**

- `lib/controllers/api/spree/api/prices_controller.rb`
- `lib/views/api/spree/api/prices/{index,show,_price}.json.jbuilder`

**Migrations** — `db/migrate/`, four of them, ordered.

These paths are the conventions `SolidusSupport::EngineExtensions` autoloads; see `enable_solidus_engine_support` in solidus_support 0.15.

---

## Phase 0 — Scaffold

### Task 1: Generate the gem skeleton

**Files:**
- Create: whole gem tree via generator
- Modify: `solidus_advanced_pricing.gemspec`

- [ ] **Step 1: Run the generator into the existing directory**

The repo already exists with `docs/` committed. Generate in place.

```bash
cd /Users/pat.mcmorran/RubymineProjects/solidus_advanced_pricing
solidus extension .
```

`solidus` is already on PATH from the installed `solidus_dev_support` gem. Do NOT prefix with
`bundle exec` — there is no Gemfile yet, so it would fail.

If the generator prompts to overwrite anything under `docs/`, decline.

- [ ] **Step 2: Set dependencies in the gemspec**

Replace the dependency block in `solidus_advanced_pricing.gemspec`:

```ruby
  spec.required_ruby_version = '>= 3.1'

  spec.add_dependency 'deface', '~> 1.9'
  spec.add_dependency 'solidus_core', ['>= 4.0', '< 5']
  spec.add_dependency 'solidus_support', '~> 0.14'

  spec.add_development_dependency 'solidus_backend', ['>= 4.0', '< 5']
  spec.add_development_dependency 'solidus_api', ['>= 4.0', '< 5']
  spec.add_development_dependency 'solidus_dev_support', '~> 2.12'
```

`solidus_backend`, `solidus_api` and `solidus_admin` are development dependencies only — the engine guards on their presence at runtime.

- [ ] **Step 3: Build the dummy app**

```bash
bin/rake extension:test_app
```

Expected: a Rails app appears at `spec/dummy`, migrations run, no errors.

- [ ] **Step 4: Run the empty suite**

```bash
bundle exec rspec
```

Expected: `0 examples, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: scaffold solidus_advanced_pricing extension"
```

### Task 2: Add the price type factory file

**Files:**
- Modify: `lib/solidus_advanced_pricing/testing_support/factories.rb`
- Create: `lib/solidus_advanced_pricing/testing_support/factories/price_type_factory.rb`

- [ ] **Step 1: Write the factory**

Create `lib/solidus_advanced_pricing/testing_support/factories/price_type_factory.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :price_type, class: 'SolidusAdvancedPricing::PriceType' do
    sequence(:name) { |n| "Price Type #{n}" }
    sequence(:code) { |n| "price_type_#{n}" }
    position { 100 }
    default { false }

    trait :default do
      default { true }
    end

    trait :discarded do
      deleted_at { Time.current }
    end
  end
end
```

- [ ] **Step 2: Leave `factories.rb` alone**

Do NOT modify `lib/solidus_advanced_pricing/testing_support/factories.rb`. The generated
`FactoryBot.define do end` is correct as-is.

`spec/spec_helper.rb` already calls
`SolidusDevSupport::TestingSupport::Factories.load_for(SolidusAdvancedPricing::Engine)`, and
`load_for` globs `lib/**/testing_support/factories{,.rb}` — registering BOTH the `factories.rb`
file and the `factories/` directory as FactoryBot definition paths. Adding a manual
`definition_file_paths.unshift` would load `price_type_factory.rb` twice and raise a duplicate
factory registration error.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test: add price type factory"
```

Note: this factory will not load successfully until Task 3 defines the model. That is expected — nothing references it yet.

---

## Phase 1 — PriceType

### Task 3: Create the price types table and model

**Files:**
- Create: `db/migrate/20260915000001_create_solidus_advanced_pricing_price_types.rb`
- Create: `app/models/solidus_advanced_pricing/price_type.rb`
- Test: `spec/models/solidus_advanced_pricing/price_type_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/solidus_advanced_pricing/price_type_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidusAdvancedPricing::PriceType do
  it 'requires a name' do
    price_type = described_class.new(code: 'x')
    expect(price_type).not_to be_valid
    expect(price_type.errors[:name]).to be_present
  end

  it 'requires a unique code' do
    create(:price_type, code: 'wholesale')
    duplicate = described_class.new(name: 'Other', code: 'wholesale')
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:code]).to be_present
  end

  it 'is soft deletable' do
    price_type = create(:price_type)
    price_type.discard
    expect(described_class.all).not_to include(price_type)
    expect(described_class.with_discarded).to include(price_type)
  end

  it 'requires a code' do
    price_type = described_class.new(name: 'X')
    expect(price_type).not_to be_valid
    expect(price_type.errors[:code]).to be_present
  end

  it 'normalizes the code to lowercase' do
    expect(create(:price_type, code: '  Wholesale  ').code).to eq('wholesale')
  end

  it 'rejects a code differing only in case' do
    create(:price_type, code: 'sale')
    expect(described_class.new(name: 'Other', code: 'SALE')).not_to be_valid
  end

  it 'keeps a discarded type\'s code reserved' do
    create(:price_type, code: 'retired').discard
    expect(described_class.new(name: 'Again', code: 'retired')).not_to be_valid
  end

  it 'allows only one default at a time' do
    first = create(:price_type, :default)
    second = create(:price_type, :default)
    expect(first.reload).not_to be_default
    expect(described_class.where(default: true)).to contain_exactly(second)
  end

  it 'promotes the only type to default automatically' do
    expect(create(:price_type).reload).to be_default
  end

  describe '.default' do
    it 'returns the flagged type' do
      default_type = create(:price_type, :default)
      expect(described_class.default).to eq(default_type)
    end

    it 'returns nil when nothing is flagged' do
      expect(described_class.default).to be_nil
    end
  end

  describe '.ordered' do
    it 'orders by position then id' do
      second = create(:price_type, position: 2)
      first = create(:price_type, position: 1)
      expect(described_class.ordered.to_a).to eq([first, second])
    end
  end

  it 'uses its name as its label' do
    expect(create(:price_type, name: 'Wholesale').to_s).to eq('Wholesale')
  end
end
```

Note: the "promotes the only type to default" example means the `.default` returning nil case
only holds when the table is empty. Write it that way.

- [ ] **Step 2: Run it and watch it fail**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/price_type_spec.rb
```

Expected: FAIL — `uninitialized constant SolidusAdvancedPricing::PriceType`.

- [ ] **Step 3: Write the migration**

Create `db/migrate/20260915000001_create_solidus_advanced_pricing_price_types.rb`:

```ruby
# frozen_string_literal: true

class CreateSolidusAdvancedPricingPriceTypes < ActiveRecord::Migration[7.0]
  def change
    create_table :solidus_advanced_pricing_price_types do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.integer :position, null: false, default: 0
      t.boolean :default, null: false, default: false
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :solidus_advanced_pricing_price_types, :code, unique: true
    add_index :solidus_advanced_pricing_price_types, :deleted_at
  end
end
```

- [ ] **Step 4: Write the model**

Create `app/models/solidus_advanced_pricing/price_type.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
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

    # Returns the price type every price falls back to, or nil before seeding.
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
    # rows can carry `default: true`, and Task 6 memoizes the default id per
    # process — two workers could memoize different ids and price lookups would
    # diverge by worker.
    def ensure_default_exists_and_is_unique
      if default?
        self.class.where.not(id: id).update_all(default: false)
      elsif self.class.where(default: true).where.not(id: id).none?
        self.default = true
      end
    end
  end
end
```

**Codes are permanent.** Uniqueness is deliberately NOT scoped to kept records:
`UniquenessValidator` starts from `klass.unscoped`, so a discarded type keeps its code
reserved. Retiring `clearance` and later wanting it back means restoring that record, not
creating a second one. This avoids partial indexes, which MySQL does not support at all.
Task 5's seeds must therefore use `with_discarded`.

- [ ] **Step 5: Migrate the dummy app and run the test**

```bash
bin/rake extension:test_app && bundle exec rspec spec/models/solidus_advanced_pricing/price_type_spec.rb
```

Expected: PASS, 3 examples.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add PriceType model"
```

### Task 4: Guard the default price type

**Files:**
- Modify: `app/models/solidus_advanced_pricing/price_type.rb`
- Test: `spec/models/solidus_advanced_pricing/price_type_spec.rb`

- [ ] **Step 1: Write the failing tests**

Append inside the `RSpec.describe` block in `spec/models/solidus_advanced_pricing/price_type_spec.rb`:

```ruby
  describe 'the default type' do
    let!(:default_type) { create(:price_type, code: 'default', default: true) }

    it 'cannot be discarded' do
      expect(default_type.discard).to be(false)
      expect(default_type.errors[:base]).to be_present
      expect(default_type.reload).to be_kept
    end

    it 're-promotes itself rather than leaving the store with no default' do
      default_type.update!(default: false)
      expect(default_type.reload).to be_default
    end

    it 'steps down when another type is made default' do
      create(:price_type, code: 'other', default: true)
      expect(default_type.reload).not_to be_default
    end
  end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/price_type_spec.rb -e 'the default type'
```

Expected: FAIL — `discard` returns true, no errors added.

- [ ] **Step 3: Implement the guards**

In `app/models/solidus_advanced_pricing/price_type.rb`, add below the validations:

```ruby
    before_discard :prevent_discarding_default

    private

    def prevent_discarding_default
      return unless default?

      errors.add(:base, :cannot_discard_default)
      throw :abort
    end
```

Two things to understand here, both verified against `discard` 2.0.0:

1. **The guard MUST be `before_discard`, not a validation.** `Discard::Model#discard` is
   `update_attribute(discard_column, Time.current)`, which skips validations entirely — a
   `validate :cannot_discard_default` would never fire. `Discard::Model` defines
   `define_model_callbacks :discard` for exactly this purpose, and `throw :abort` aborts it.
2. **Task 3 already handles the "flag cleared" half.** `ensure_default_exists_and_is_unique`
   re-promotes a record when clearing its flag would leave no default, so the validation the
   earlier draft of this plan specified is unnecessary and would fight the callback. Do not
   add it.

- [ ] **Step 4: Add the error translations**

In `config/locales/en.yml`, under the existing `en:` key:

```yaml
en:
  activerecord:
    errors:
      models:
        solidus_advanced_pricing/price_type:
          attributes:
            base:
              cannot_discard_default: "The default price type cannot be deleted."
              referenced_by_prices: "This price type is still used by one or more prices and cannot be deleted. Retire it instead."
```

- [ ] **Step 5: Run the full model spec**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/price_type_spec.rb
```

Expected: PASS, 6 examples.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: guard the default price type against discard and flag clearing"
```

### Task 5: Seed the five price types

**Files:**
- Create: `db/migrate/20260915000002_seed_solidus_advanced_pricing_price_types.rb`
- Test: `spec/migrations/seed_price_types_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/migrations/seed_price_types_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'seeded price types' do
  # These assert the seeds are present and correctly shaped. Note they pass via
  # the `before` hook in spec_helper as well as via the migration; the migration
  # itself is exercised by running `bin/rake extension:test_app`.
  it 'ships five types in order' do
    expect(SolidusAdvancedPricing::PriceType.ordered.pluck(:code)).to eq(
      %w[default wholesale sale clearance employee]
    )
  end

  it 'marks only default as the default' do
    expect(SolidusAdvancedPricing::PriceType.where(default: true).pluck(:code)).to eq(['default'])
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/migrations/seed_price_types_spec.rb
```

Expected: FAIL — `[]` does not equal the expected array.

- [ ] **Step 3: Write the seeding migration**

Create `db/migrate/20260915000002_seed_solidus_advanced_pricing_price_types.rb`:

```ruby
# frozen_string_literal: true

class SeedSolidusAdvancedPricingPriceTypes < ActiveRecord::Migration[7.0]
  SEEDS = [
    { code: 'default',   name: 'Default',   position: 1, default: true },
    { code: 'wholesale', name: 'Wholesale', position: 2, default: false },
    { code: 'sale',      name: 'Sale',      position: 3, default: false },
    { code: 'clearance', name: 'Clearance', position: 4, default: false },
    { code: 'employee',  name: 'Employee',  position: 5, default: false }
  ].freeze

  def up
    now = Time.current

    # Matches on code across discarded rows too: codes stay reserved after a
    # discard (see Task 3), so a `kept`-scoped check would try to insert a
    # duplicate and hit the unique index.
    SEEDS.each do |attrs|
      next if price_types.where(code: attrs[:code]).exists?

      price_types.insert_all([attrs.merge(created_at: now, updated_at: now)])
    end
  end

  def down
    price_types.where(code: SEEDS.map { |attrs| attrs[:code] }).delete_all
  end

  private

  def price_types
    @price_types ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'solidus_advanced_pricing_price_types'
    end
  end
end
```

Using an anonymous model rather than `SolidusAdvancedPricing::PriceType` keeps the migration
independent of the app model — critically, it bypasses both `default_scope { kept }` (so
discarded rows are seen) and `ensure_default_exists_and_is_unique` (so inserting five rows,
four of them `default: false`, does not trigger four rounds of demotion). Keying on `code`
makes it idempotent.

`default` is a reserved word in MySQL and PostgreSQL. Go through `insert_all` as shown, never
raw `execute("INSERT INTO ... (default) ...")`, so ActiveRecord quotes the identifier.

The five positions are distinct on purpose: `scope :ordered` falls back to `id` on ties, and
the seed order is what admins see in every dropdown.

- [ ] **Step 4: Add `PriceType.seed!` and call it from the test suite**

**This step is not optional — without it every later task breaks.**
`solidus_dev_support`'s rails_helper does `config.before(:suite) { DatabaseCleaner.clean_with :truncation }`,
which truncates the migration-seeded rows before the first example ever runs. Specs tagged `:js`
also truncate per-example. So migration seeding alone leaves
`SolidusAdvancedPricing::PriceType.find_by(code: 'default')` returning `nil` throughout the suite,
which breaks this task's spec, Task 7's `assign_default_price_type` (NOT NULL violation), Task 10's
`default_price_attributes` pinning, and Task 17's backward-compatibility specs.

Add to `app/models/solidus_advanced_pricing/price_type.rb`:

```ruby
    SEEDS = [
      { code: 'default',   name: 'Default',   position: 1, default: true },
      { code: 'wholesale', name: 'Wholesale', position: 2, default: false },
      { code: 'sale',      name: 'Sale',      position: 3, default: false },
      { code: 'clearance', name: 'Clearance', position: 4, default: false },
      { code: 'employee',  name: 'Employee',  position: 5, default: false }
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
```

`with_discarded` matters: codes stay reserved after a discard, so a `kept`-scoped lookup would
try to create a duplicate and hit the unique index.

Then in `spec/spec_helper.rb`, inside the `RSpec.configure` block:

```ruby
  config.before do
    SolidusAdvancedPricing::PriceType.seed!
  end
```

`before(:each)` rather than `before(:suite)`: the `around(:each)` hook wraps each example in
`DatabaseCleaner.cleaning`, so seeding here runs inside the transaction and is re-established for
every example, including truncating `:js` ones. It is five `find_or_create_by` calls per example —
cheap, and it makes every spec deterministic.

- [ ] **Step 5: Migrate and run the test**

```bash
bin/rake extension:test_app && bundle exec rspec spec/migrations/seed_price_types_spec.rb
```

Expected: PASS, 2 examples.

- [ ] **Step 6: Re-check the Task 3 specs**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/price_type_spec.rb
```

Two Task 3 examples assume an unseeded table and will now fail. Fix the **expectations**, not the
implementation:

- `'promotes the only type to default automatically'` — a default now always exists, so nothing
  auto-promotes. Change it to assert that a new type created alongside the seeds is NOT default:
  `expect(create(:price_type).reload).not_to be_default`
- `'.default returns nil when the table is empty'` — delete it and replace with
  `it('returns the seeded default') { expect(described_class.default.code).to eq('default') }`

Also check `.ordered`: the seeds occupy positions 1–5, so that example must use positions above 5
or scope itself to the records it creates.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: seed default, wholesale, sale, clearance and employee price types"
```

### Task 6: Expose a memoized default type lookup

**Files:**
- Modify: `app/models/solidus_advanced_pricing/price_type.rb`
- Create: `app/models/solidus_advanced_pricing/price_type_cache.rb`
- Test: `spec/models/solidus_advanced_pricing/price_type_cache_spec.rb`

`PricingOptions.default_price_attributes` runs on every pricing lookup, so it must not hit the database each time.

- [ ] **Step 1: Write the failing test**

Create `spec/models/solidus_advanced_pricing/price_type_cache_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidusAdvancedPricing::PriceTypeCache do
  before { described_class.clear }

  it 'returns the id of the default price type' do
    expected = SolidusAdvancedPricing::PriceType.find_by(code: 'default').id
    expect(described_class.default_id).to eq(expected)
  end

  it 'does not query again on a second call' do
    described_class.default_id
    expect { described_class.default_id }.not_to make_database_queries
  end

  it 'is cleared when a price type is saved' do
    described_class.default_id
    create(:price_type)
    expect(described_class.instance_variable_defined?(:@default_id)).to be(false)
  end

  it 'caches a nil result instead of re-querying forever' do
    SolidusAdvancedPricing::PriceType.with_discarded.update_all(default: false)
    described_class.clear
    described_class.default_id
    expect { described_class.default_id }.not_to make_database_queries
  end
end
```

`make_database_queries` comes from `db-query-matchers`. Add it to the gemspec development dependencies:

```ruby
  spec.add_development_dependency 'db-query-matchers', '~> 0.12'
```

and require it in `spec/spec_helper.rb` above the `RSpec.configure` block:

```ruby
require 'db_query_matchers'
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle install && bundle exec rspec spec/models/solidus_advanced_pricing/price_type_cache_spec.rb
```

Expected: FAIL — `uninitialized constant SolidusAdvancedPricing::PriceTypeCache`.

- [ ] **Step 3: Write the cache**

Create `app/models/solidus_advanced_pricing/price_type_cache.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
  # Process-local memoization for values read on every pricing lookup.
  # Cleared by an +after_commit+ on PriceType and Spree::Price.
  module PriceTypeCache
    class << self
      # `defined?` rather than `||=`: before seeding, the default id is legitimately
      # nil, and `||=` would re-query on every single pricing lookup — the exact
      # hot path this exists to avoid.
      def default_id
        return @default_id if defined?(@default_id)

        @default_id = PriceType.with_discarded.find_by(default: true)&.id
      end

      def clear
        remove_instance_variable(:@default_id) if defined?(@default_id)
      end
    end
  end
end
```

- [ ] **Step 4: Clear it when a type changes**

In `app/models/solidus_advanced_pricing/price_type.rb`, add above the `private` keyword:

```ruby
    after_commit { SolidusAdvancedPricing::PriceTypeCache.clear }
```

- [ ] **Step 5: Run the test**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/price_type_cache_spec.rb
```

Expected: PASS, 3 examples.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: memoize the default price type id"
```

---

## Phase 2 — Price columns

### Task 7: Add the columns to spree_prices

**Files:**
- Create: `db/migrate/20260915000003_add_advanced_pricing_to_spree_prices.rb`
- Create: `db/migrate/20260915000004_backfill_price_type_on_spree_prices.rb`
- Test: `spec/models/spree/price_columns_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/spree/price_columns_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Price do
  it 'has the advanced pricing columns' do
    expect(described_class.column_names).to include(
      'price_type_id', 'role_id', 'valid_from', 'valid_to', 'admin_notes'
    )
  end

  it 'defaults a new price to the default price type' do
    price = create(:price)
    expect(price.price_type.code).to eq('default')
  end

  it 'backfills existing prices onto the default type' do
    expect(described_class.where(price_type_id: nil).count).to eq(0)
  end

  it 'keeps its price type after the type is retired' do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: 'sale')
    price = create(:price, price_type: sale_type)
    sale_type.discard
    expect(price.reload.price_type).to eq(sale_type)
  end

  it 'blocks destroying a type that a discarded price still references' do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: 'sale')
    price = create(:price, price_type: sale_type)
    price.discard
    expect(sale_type.destroy).to be(false)
    expect(SolidusAdvancedPricing::PriceType.with_discarded).to include(sale_type)
  end
end
```

The "keeps its price type after the type is retired" example is the whole point of declaring
`belongs_to :price_type, -> { with_discarded }`. Without the scope, `Spree::SoftDeletable`'s
`default_scope { kept }` makes `price.price_type` return nil for a retired type, and
"Overstock Sale of 2012" silently loses its label. It is easy to regress, so it is pinned.

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/spree/price_columns_spec.rb
```

Expected: FAIL — column names do not include `price_type_id`.

- [ ] **Step 3: Write the column migration**

Create `db/migrate/20260915000003_add_advanced_pricing_to_spree_prices.rb`:

```ruby
# frozen_string_literal: true

class AddAdvancedPricingToSpreePrices < ActiveRecord::Migration[7.0]
  def change
    add_column :spree_prices, :price_type_id, :bigint
    add_column :spree_prices, :role_id, :bigint
    add_column :spree_prices, :valid_from, :datetime
    add_column :spree_prices, :valid_to, :datetime
    add_column :spree_prices, :admin_notes, :text

    add_index :spree_prices, :price_type_id
    add_index :spree_prices, :role_id
    add_index :spree_prices,
      [:variant_id, :currency, :country_iso, :role_id, :valid_from, :valid_to],
      name: 'index_spree_prices_on_advanced_pricing_lookup'

    add_foreign_key :spree_prices, :solidus_advanced_pricing_price_types, column: :price_type_id
    add_foreign_key :spree_prices, :spree_roles, column: :role_id
  end
end
```

- [ ] **Step 4: Write the backfill migration**

Create `db/migrate/20260915000004_backfill_price_type_on_spree_prices.rb`:

```ruby
# frozen_string_literal: true

class BackfillPriceTypeOnSpreePrices < ActiveRecord::Migration[7.0]
  def up
    default_id = select_value(<<~SQL.squish)
      SELECT id FROM solidus_advanced_pricing_price_types WHERE code = 'default' LIMIT 1
    SQL

    raise 'No default price type found; run the seed migration first.' if default_id.nil?

    execute <<~SQL.squish
      UPDATE spree_prices SET price_type_id = #{default_id.to_i} WHERE price_type_id IS NULL
    SQL

    change_column_null :spree_prices, :price_type_id, false
  end

  def down
    change_column_null :spree_prices, :price_type_id, true
  end
end
```

A single `UPDATE` rather than row-by-row — this table is large in real stores.

- [ ] **Step 5: Set the column default in the model decorator**

Create `app/decorators/models/solidus_advanced_pricing/spree/price_decorator.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module PriceDecorator
      def self.prepended(base)
        # with_discarded: a price keeps its type after an admin retires it.
        base.belongs_to :price_type,
          -> { with_discarded },
          class_name: 'SolidusAdvancedPricing::PriceType',
          inverse_of: :prices

        base.belongs_to :role,
          class_name: '::Spree::Role',
          optional: true

        base.before_validation :assign_default_price_type
      end

      private

      def assign_default_price_type
        self.price_type_id ||= SolidusAdvancedPricing::PriceTypeCache.default_id
      end

      ::Spree::Price.prepend self
    end
  end
end
```

- [ ] **Step 6: Add the association to PriceType itself**

In `app/models/solidus_advanced_pricing/price_type.rb`, replace the `NOTE:` comment left by
Task 3 with the real association:

```ruby
    has_many :prices,
      class_name: "Spree::Price",
      foreign_key: :price_type_id,
      inverse_of: :price_type

    # Not `dependent: :restrict_with_error` — that check is default-scoped and
    # misses discarded prices, which then trip the FK on DELETE.
    before_destroy :prevent_destroying_referenced_type
```

and in the existing `private` section:

```ruby
    def prevent_destroying_referenced_type
      return unless prices.with_discarded.exists?

      errors.add(:base, :referenced_by_prices)
      throw :abort
    end
```

This belongs in the model, **not** in a `PriceType.class_eval` block inside the decorator.
Decorator files are re-`load`ed on every `to_prepare`, so a bare `class_eval` at module-body
level would re-run `before_destroy` on each reload and register the callback repeatedly — the
guard would fire two, three, four times in development. Association declarations on our own
model are safe because Rails resolves the `Spree::Price` constant lazily; it does not need to
exist when the file loads, only when the association is used.

Add the locale key under the `price_type` attributes block in `config/locales/en.yml`:

```yaml
              referenced_by_prices: "This price type is still used by one or more prices and cannot be deleted. Retire it instead."
```

- [ ] **Step 7: Migrate and run**

```bash
bin/rake extension:test_app && bundle exec rspec spec/models/spree/price_columns_spec.rb
```

Expected: PASS, 5 examples.

**Watch for a foreign key / truncation interaction.** This task adds the first foreign keys
pointing at `solidus_advanced_pricing_price_types`. `solidus_dev_support` runs
`DatabaseCleaner.clean_with :truncation` before the suite and per `:js` example. If truncation
ordering or FK enforcement causes errors, report what you see rather than dropping the foreign
keys — they are the thing keeping `price_type_id NOT NULL` honest.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add price type, role, validity window and admin notes to prices"
```

### Task 8: Validate the validity window

**Files:**
- Modify: `app/decorators/models/solidus_advanced_pricing/spree/price_decorator.rb`
- Test: `spec/models/spree/price_validations_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/spree/price_validations_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Price do
  it 'rejects a window that ends before it starts' do
    price = build(:price, valid_from: Time.zone.parse('2026-02-01'), valid_to: Time.zone.parse('2026-01-01'))
    expect(price).not_to be_valid
    expect(price.errors[:valid_to]).to be_present
  end

  it 'accepts a window that ends after it starts' do
    price = build(:price, valid_from: Time.zone.parse('2026-01-01'), valid_to: Time.zone.parse('2026-02-01'))
    expect(price).to be_valid
  end

  it 'accepts an open-ended window' do
    expect(build(:price, valid_from: nil, valid_to: nil)).to be_valid
    expect(build(:price, valid_from: Time.current, valid_to: nil)).to be_valid
    expect(build(:price, valid_from: nil, valid_to: Time.current)).to be_valid
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/spree/price_validations_spec.rb
```

Expected: FAIL — the reversed window is considered valid.

- [ ] **Step 3: Add the validation**

In `app/decorators/models/solidus_advanced_pricing/spree/price_decorator.rb`, inside `self.prepended`, below `before_validation`:

```ruby
        base.validate :valid_to_after_valid_from
```

and in the `private` section:

```ruby
      def valid_to_after_valid_from
        return if valid_from.blank? || valid_to.blank?
        return if valid_to > valid_from

        errors.add(:valid_to, :must_be_after_valid_from)
      end
```

Add to `config/locales/en.yml` under the `spree/price` attributes:

```yaml
        spree/price:
          attributes:
            valid_to:
              must_be_after_valid_from: "must be after the valid from date"
```

- [ ] **Step 4: Run the test**

```bash
bundle exec rspec spec/models/spree/price_validations_spec.rb
```

Expected: PASS, 3 examples.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: validate that valid_to falls after valid_from"
```

### Task 9: Add the eligibility scopes

**Files:**
- Modify: `app/decorators/models/solidus_advanced_pricing/spree/price_decorator.rb`
- Test: `spec/models/spree/price_scopes_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/spree/price_scopes_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Price do
  let(:now) { Time.zone.parse('2026-06-15 12:00:00') }
  let(:variant) { create(:variant) }
  let(:role) { create(:role, name: 'wholesale') }

  describe '.valid_at' do
    let!(:open_ended) { create(:price, variant: variant) }
    let!(:current)    { create(:price, variant: variant, valid_from: now - 1.day, valid_to: now + 1.day) }
    let!(:expired)    { create(:price, variant: variant, valid_from: now - 5.days, valid_to: now - 1.day) }
    let!(:future)     { create(:price, variant: variant, valid_from: now + 1.day) }

    it 'keeps open-ended and currently valid prices only' do
      expect(described_class.valid_at(now)).to contain_exactly(open_ended, current)
    end

    it 'treats valid_to as exclusive' do
      expect(described_class.valid_at(now + 1.day)).not_to include(current)
    end
  end

  describe '.visible_to_roles' do
    let!(:untargeted) { create(:price, variant: variant, role: nil) }
    let!(:targeted)   { create(:price, variant: variant, role: role) }

    it 'returns only untargeted prices for a guest' do
      expect(described_class.visible_to_roles([])).to contain_exactly(untargeted)
    end

    it 'returns both for a customer holding the role' do
      expect(described_class.visible_to_roles([role.id])).to contain_exactly(untargeted, targeted)
    end
  end

  describe '.for_price_type' do
    let(:wholesale_type) { SolidusAdvancedPricing::PriceType.find_by(code: 'wholesale') }
    let!(:default_price)   { create(:price, variant: variant) }
    let!(:wholesale_price) { create(:price, variant: variant, price_type: wholesale_type) }

    it 'filters by type' do
      expect(described_class.for_price_type(wholesale_type)).to contain_exactly(wholesale_price)
    end
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/spree/price_scopes_spec.rb
```

Expected: FAIL — `undefined method 'valid_at'`.

- [ ] **Step 3: Add the scopes**

In `app/decorators/models/solidus_advanced_pricing/spree/price_decorator.rb`, inside `self.prepended`:

```ruby
        base.scope :valid_at, ->(time) {
          where(arel_table[:valid_from].eq(nil).or(arel_table[:valid_from].lteq(time)))
            .where(arel_table[:valid_to].eq(nil).or(arel_table[:valid_to].gt(time)))
        }

        base.scope :visible_to_roles, ->(role_ids) {
          where(role_id: [nil, *role_ids])
        }

        base.scope :for_price_type, ->(price_type) {
          where(price_type_id: price_type)
        }
```

`valid_to` is exclusive so that a window ending at midnight and the next one starting at midnight do not both match.

- [ ] **Step 4: Run the test**

```bash
bundle exec rspec spec/models/spree/price_scopes_spec.rb
```

Expected: PASS, 5 examples.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add valid_at, visible_to_roles and for_price_type scopes"
```

---

## Phase 3 — PricingOptions

### Task 10: Build the pricing options subclass

**Files:**
- Create: `app/models/solidus_advanced_pricing/pricing_options.rb`
- Test: `spec/models/solidus_advanced_pricing/pricing_options_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/solidus_advanced_pricing/pricing_options_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidusAdvancedPricing::PricingOptions do
  let(:default_type_id) { SolidusAdvancedPricing::PriceType.find_by(code: 'default').id }

  describe 'defaults' do
    subject(:options) { described_class.new }

    it 'pins the price type to the default type' do
      expect(options.desired_attributes[:price_type_id]).to eq(default_type_id)
    end

    it 'pins role_id to nil so the admin sees the untargeted price' do
      expect(options.desired_attributes).to have_key(:role_id)
      expect(options.desired_attributes[:role_id]).to be_nil
    end

    it 'treats a caller with no user as a guest' do
      expect(options.customer_role_ids).to eq([])
    end

    it 'defaults the evaluation time to now' do
      freeze_time do
        expect(options.at).to eq(Time.current)
      end
    end
  end

  it 'keeps at and customer_role_ids out of desired_attributes' do
    options = described_class.new(at: Time.current, customer_role_ids: [1])
    expect(options.desired_attributes).not_to have_key(:at)
    expect(options.desired_attributes).not_to have_key(:customer_role_ids)
  end

  it 'does not mutate the hash it is given' do
    attributes = { at: Time.current, customer_role_ids: [1] }
    described_class.new(attributes)
    expect(attributes).to have_key(:at)
  end

  it 'can be built for a price' do
    price = create(:price)
    options = described_class.from_price(price)
    expect(options.desired_attributes[:price_type_id]).to eq(price.price_type_id)
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/pricing_options_spec.rb
```

Expected: FAIL — `uninitialized constant SolidusAdvancedPricing::PricingOptions`.

- [ ] **Step 3: Write the class**

Create `app/models/solidus_advanced_pricing/pricing_options.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
  # Adds customer context to Solidus' pricing options.
  #
  # +desired_attributes+ describes the *price being sought* and may only contain
  # assignable Spree::Price columns, because core calls
  # +prices.build(default_price_attributes)+. The customer context (+at+ and
  # +customer_role_ids+) describes *who is asking* and lives outside that hash.
  class PricingOptions < ::Spree::Variant::PricingOptions
    attr_reader :at, :customer_role_ids

    def self.default_price_attributes
      super.merge(
        price_type_id: SolidusAdvancedPricing::PriceTypeCache.default_id,
        role_id: nil
      )
    end

    # price_type_id: nil means "any type competes". default_price_attributes pins it
    # to the default type so the admin edits the base price; customers must not inherit
    # that pin or a sale price could never be selected.
    def self.from_line_item(line_item)
      options = super
      new(
        options.desired_attributes.merge(
          price_type_id: nil,
          customer_role_ids: pricing_relevant_role_ids(line_item.order&.user)
        )
      )
    end

    def self.from_context(context)
      options = super
      new(
        options.desired_attributes.merge(
          price_type_id: nil,
          customer_role_ids: pricing_relevant_role_ids(context.try(:current_spree_user))
        )
      )
    end

    def self.from_price(price)
      new(
        currency: price.currency,
        country_iso: price.country_iso,
        price_type_id: price.price_type_id,
        role_id: price.role_id
      )
    end

    # Narrows a customer's roles to those that actually appear on a price.
    # Selection is unaffected — a role no price references can never match —
    # but it collapses cache key cardinality dramatically.
    def self.pricing_relevant_role_ids(user)
      return [] if user.nil?

      user.spree_role_ids & SolidusAdvancedPricing::PriceTypeCache.pricing_role_ids
    end

    def initialize(desired_attributes = {})
      attributes = desired_attributes.dup
      @at = attributes.key?(:at) ? attributes.delete(:at) : Time.current
      @customer_role_ids = Array(attributes.delete(:customer_role_ids))
      super(attributes)
    end
  end
end
```

- [ ] **Step 4: Add the pricing role cache**

In `app/models/solidus_advanced_pricing/price_type_cache.rb`, add inside `class << self`:

```ruby
      def pricing_role_ids
        @pricing_role_ids ||= ::Spree::Price.distinct.pluck(:role_id).compact
      end
```

and extend `clear`:

```ruby
      def clear
        @default_id = nil
        @pricing_role_ids = nil
      end
```

In `app/decorators/models/solidus_advanced_pricing/spree/price_decorator.rb`, inside `self.prepended`:

```ruby
        base.after_commit { SolidusAdvancedPricing::PriceTypeCache.clear }
```

- [ ] **Step 5: Run the test**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/pricing_options_spec.rb
```

Expected: PASS, 7 examples.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add PricingOptions carrying customer time and role context"
```

### Task 11: Add the cache granularity preference

**Files:**
- Create: `app/decorators/models/solidus_advanced_pricing/spree/app_configuration_decorator.rb`
- Test: `spec/models/spree/app_configuration_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/spree/app_configuration_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::AppConfiguration do
  it 'defaults the cache granularity to 60 seconds' do
    expect(Spree::Config.advanced_pricing_cache_granularity).to eq(60)
  end

  it 'can be set to 0 to disable time bucketing' do
    Spree::Config.advanced_pricing_cache_granularity = 0
    expect(Spree::Config.advanced_pricing_cache_granularity).to eq(0)
  ensure
    Spree::Config.advanced_pricing_cache_granularity = 60
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/spree/app_configuration_spec.rb
```

Expected: FAIL — `undefined method 'advanced_pricing_cache_granularity'`.

- [ ] **Step 3: Add the preference**

Create `app/decorators/models/solidus_advanced_pricing/spree/app_configuration_decorator.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module AppConfigurationDecorator
      def self.prepended(base)
        # Seconds. Price validity is bucketed to this granularity in cache keys,
        # trading up to one bucket of staleness for a usable cache hit rate.
        # Set to 0 to key on nothing (prices may be cached past their window).
        base.preference :advanced_pricing_cache_granularity, :integer, default: 60
      end

      ::Spree::AppConfiguration.prepend self
    end
  end
end
```

Note: the spec document said "set it to `nil`". An integer preference coerces `nil` to `0`, so `0` is the documented disable value. Update the spec's Caching section to say `0`.

- [ ] **Step 4: Run the test**

```bash
bundle exec rspec spec/models/spree/app_configuration_spec.rb
```

Expected: PASS, 2 examples.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add advanced_pricing_cache_granularity preference"
```

### Task 12: Override the cache key

**Files:**
- Modify: `app/models/solidus_advanced_pricing/pricing_options.rb`
- Test: `spec/models/solidus_advanced_pricing/pricing_options_cache_key_spec.rb`

This is the leak-prevention task. Without it a wholesale price renders into a fragment cache and is served to guests.

- [ ] **Step 1: Write the failing test**

Create `spec/models/solidus_advanced_pricing/pricing_options_cache_key_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidusAdvancedPricing::PricingOptions, 'cache keys' do
  let(:now) { Time.zone.parse('2026-06-15 12:00:00') }

  it 'differs between a guest and a role-holding customer' do
    guest = described_class.new(at: now, customer_role_ids: [])
    wholesale = described_class.new(at: now, customer_role_ids: [7])
    expect(guest.cache_key).not_to eq(wholesale.cache_key)
  end

  it 'does not depend on role order' do
    a = described_class.new(at: now, customer_role_ids: [7, 3])
    b = described_class.new(at: now, customer_role_ids: [3, 7])
    expect(a.cache_key).to eq(b.cache_key)
  end

  it 'buckets time so nearby requests share a key' do
    a = described_class.new(at: now, customer_role_ids: [])
    b = described_class.new(at: now + 10.seconds, customer_role_ids: [])
    expect(a.cache_key).to eq(b.cache_key)
  end

  it 'changes once the bucket rolls over' do
    a = described_class.new(at: now, customer_role_ids: [])
    b = described_class.new(at: now + 61.seconds, customer_role_ids: [])
    expect(a.cache_key).not_to eq(b.cache_key)
  end

  it 'omits the time component when granularity is 0' do
    with_unfrozen_spree_preference_store do
      Spree::Config.advanced_pricing_cache_granularity = 0
      a = described_class.new(at: now, customer_role_ids: [])
      b = described_class.new(at: now + 1.year, customer_role_ids: [])
      expect(a.cache_key).to eq(b.cache_key)
    end
  end
end
```

**Writing to `Spree::Config` in a spec needs `with_unfrozen_spree_preference_store`.**
`solidus_dev_support`'s rails_helper calls `Spree::TestingSupport::Preferences.freeze_preferences`
in `before(:suite)`, and the per-example reset that used to undo it was removed for Solidus >= 2.9.
A bare assignment raises `FrozenError: can't modify frozen Hash`. Reading a preference needs no
wrapper — only the example above, which flips the value, does.

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/pricing_options_cache_key_spec.rb
```

Expected: FAIL — the guest and wholesale keys are equal.

- [ ] **Step 3: Override cache_key**

In `app/models/solidus_advanced_pricing/pricing_options.rb`, add as a public instance method:

```ruby
    # Core keys only on +desired_attributes+. Customer context lives outside that
    # hash, so without this override a role-targeted price would be cached and
    # then served to a guest.
    def cache_key
      [super, roles_cache_component, time_cache_component].compact.join('/')
    end

    private

    def roles_cache_component
      return 'r-none' if customer_role_ids.empty?

      "r-#{customer_role_ids.sort.join('-')}"
    end

    def time_cache_component
      granularity = ::Spree::Config.advanced_pricing_cache_granularity.to_i
      return nil if granularity <= 0
      return nil if at.nil?

      "t-#{at.to_i / granularity}"
    end
```

- [ ] **Step 4: Run the test**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/pricing_options_cache_key_spec.rb
```

Expected: PASS, 5 examples.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix: key pricing caches on customer roles and a time bucket"
```

---

## Phase 4 — PriceSelector

### Task 13: Select by currency, window and role

**Files:**
- Create: `app/models/solidus_advanced_pricing/price_selector.rb`
- Test: `spec/models/solidus_advanced_pricing/price_selector_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/solidus_advanced_pricing/price_selector_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidusAdvancedPricing::PriceSelector do
  subject(:selector) { described_class.new(variant) }

  let(:variant) { create(:variant, price: 100) }
  let(:now) { Time.zone.parse('2026-06-15 12:00:00') }
  let(:wholesale_role) { create(:role, name: 'wholesale') }

  def options(**overrides)
    SolidusAdvancedPricing::PricingOptions.new(
      { currency: 'USD', country_iso: nil, at: now, customer_role_ids: [] }.merge(overrides)
    )
  end

  it 'exposes the matching pricing options class' do
    expect(described_class.pricing_options_class).to eq(SolidusAdvancedPricing::PricingOptions)
  end

  it 'ignores prices in another currency' do
    create(:price, variant: variant, currency: 'EUR', amount: 1)
    expect(selector.price_for_options(options).currency).to eq('USD')
  end

  it 'ignores an expired price' do
    create(:price, variant: variant, amount: 1, valid_from: now - 5.days, valid_to: now - 1.day)
    expect(selector.price_for_options(options).amount).to eq(100)
  end

  it 'ignores a future price' do
    create(:price, variant: variant, amount: 1, valid_from: now + 1.day)
    expect(selector.price_for_options(options).amount).to eq(100)
  end

  it 'uses a price whose window is currently open' do
    create(:price, variant: variant, amount: 80, valid_from: now - 1.day, valid_to: now + 1.day)
    expect(selector.price_for_options(options).amount).to eq(80)
  end

  it 'hides a role-targeted price from a guest' do
    create(:price, variant: variant, amount: 60, role: wholesale_role)
    expect(selector.price_for_options(options).amount).to eq(100)
  end

  it 'shows a role-targeted price to a customer holding that role' do
    create(:price, variant: variant, amount: 60, role: wholesale_role)
    expect(selector.price_for_options(options(customer_role_ids: [wholesale_role.id])).amount).to eq(60)
  end

  it 'returns nil when nothing is eligible' do
    variant.prices.each { |price| price.update!(valid_to: now - 1.day) }
    expect(selector.price_for_options(options)).to be_nil
  end

  it 'lets every type compete when no type is pinned' do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: 'sale')
    create(:price, variant: variant, amount: 70, price_type: sale_type)
    expect(selector.price_for_options(options).amount).to eq(70)
  end

  it 'restricts to the pinned type when one is given' do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: 'sale')
    default_type = SolidusAdvancedPricing::PriceType.find_by(code: 'default')
    create(:price, variant: variant, amount: 70, price_type: sale_type)
    result = selector.price_for_options(options(price_type_id: default_type.id))
    expect(result.amount).to eq(100)
  end
end
```

Those last two are the load-bearing pair. Together they encode the split the whole design rests
on: the admin lookup pins `price_type_id` and sees the base price, while a customer lookup
leaves it nil and lets a cheaper sale price win.

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/price_selector_spec.rb
```

Expected: FAIL — `uninitialized constant SolidusAdvancedPricing::PriceSelector`.

- [ ] **Step 3: Write the selector**

Create `app/models/solidus_advanced_pricing/price_selector.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
  # Selects a price given customer context.
  #
  # Filter -> country bucket -> cheapest. Role is eligibility only, never
  # specificity: a role match qualifies a customer to see a price, and among
  # everything visible the cheapest wins. A role-targeted price set above the
  # untargeted price therefore never applies.
  class PriceSelector < ::Spree::Variant::PriceSelector
    def self.pricing_options_class
      SolidusAdvancedPricing::PricingOptions
    end

    def price_for_options(price_options)
      candidates = eligible_prices(price_options)
      return nil if candidates.empty?

      cheapest(bucket_by_country(candidates, price_options.country_iso))
    end

    private

    def eligible_prices(price_options)
      wanted_type = price_options.desired_attributes[:price_type_id]

      variant.prices.select do |price|
        kept?(price) &&
          price.currency == price_options.currency &&
          matches_type?(price, wanted_type) &&
          valid_at?(price, price_options.at) &&
          visible_to?(price, price_options.customer_role_ids)
      end
    end

    # nil means any type competes; a pinned id restricts to it. This is what keeps
    # the admin's variant.price on the base price instead of a cheaper sale price.
    def matches_type?(price, wanted_type)
      wanted_type.nil? || price.price_type_id == wanted_type
    end

    def kept?(price)
      variant.discarded? || price.kept?
    end

    def valid_at?(price, time)
      return true if time.nil?

      (price.valid_from.nil? || price.valid_from <= time) &&
        (price.valid_to.nil? || price.valid_to > time)
    end

    def visible_to?(price, customer_role_ids)
      price.role_id.nil? || customer_role_ids.include?(price.role_id)
    end

    # Country is specificity, not competition: a country-specific price beats the
    # any-country fallback even when the fallback is cheaper.
    def bucket_by_country(candidates, country_iso)
      specific = candidates.select { |price| price.country_iso == country_iso && !price.country_iso.nil? }
      specific.presence || candidates.select { |price| price.country_iso.nil? }
    end

    def cheapest(candidates)
      candidates.min_by do |price|
        [
          price.amount,
          price.price_type&.position || 0,
          -(price.updated_at || Time.zone.now).to_i,
          -(price.id || Float::INFINITY)
        ]
      end
    end
  end
end
```

- [ ] **Step 4: Run the test**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/price_selector_spec.rb
```

Expected: PASS, 8 examples.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add PriceSelector filtering by window and role"
```

### Task 14: Prove country specificity and cheapest-wins

**Files:**
- Test: `spec/models/solidus_advanced_pricing/price_selector_precedence_spec.rb`

- [ ] **Step 1: Write the test**

Create `spec/models/solidus_advanced_pricing/price_selector_precedence_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidusAdvancedPricing::PriceSelector, 'precedence' do
  subject(:selector) { described_class.new(variant) }

  let(:variant) { create(:variant, price: 100) }
  let(:now) { Time.zone.parse('2026-06-15 12:00:00') }
  let(:wholesale_role) { create(:role, name: 'wholesale') }

  def options(**overrides)
    SolidusAdvancedPricing::PricingOptions.new(
      { currency: 'USD', country_iso: nil, at: now, customer_role_ids: [] }.merge(overrides)
    )
  end

  it 'prefers a country-specific price over a cheaper any-country price' do
    create(:country, iso: 'DE')
    create(:price, variant: variant, country_iso: 'DE', amount: 150)
    result = selector.price_for_options(options(country_iso: 'DE'))
    expect(result.amount).to eq(150)
  end

  it 'falls back to the any-country price when no country price exists' do
    create(:country, iso: 'DE')
    result = selector.price_for_options(options(country_iso: 'DE'))
    expect(result.amount).to eq(100)
  end

  it 'picks the cheapest within the winning country bucket' do
    create(:price, variant: variant, amount: 70)
    create(:price, variant: variant, amount: 85)
    expect(selector.price_for_options(options).amount).to eq(70)
  end

  it 'never applies a role price set above the untargeted price' do
    create(:price, variant: variant, amount: 120, role: wholesale_role)
    result = selector.price_for_options(options(customer_role_ids: [wholesale_role.id]))
    expect(result.amount).to eq(100)
  end

  it 'lets a customer holding two roles take the cheaper of the two' do
    employee_role = create(:role, name: 'employee')
    create(:price, variant: variant, amount: 60, role: wholesale_role)
    create(:price, variant: variant, amount: 50, role: employee_role)
    result = selector.price_for_options(
      options(customer_role_ids: [wholesale_role.id, employee_role.id])
    )
    expect(result.amount).to eq(50)
  end
end
```

- [ ] **Step 2: Run it**

```bash
bundle exec rspec spec/models/solidus_advanced_pricing/price_selector_precedence_spec.rb
```

Expected: PASS, 5 examples — the selector from Task 13 already implements this. If any fail, fix the selector, not the test.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test: pin country specificity and cheapest-wins precedence"
```

### Task 15: Register the selector

**Files:**
- Create: `lib/generators/solidus_advanced_pricing/install/templates/initializer.rb`
- Modify: `spec/spec_helper.rb`
- Test: `spec/models/spree/variant_pricing_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/spree/variant_pricing_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Variant, 'advanced pricing' do
  it 'uses the advanced price selector' do
    expect(Spree::Config.variant_price_selector_class).to eq(SolidusAdvancedPricing::PriceSelector)
  end

  it 'delegates the pricing options class from the selector' do
    expect(Spree::Config.pricing_options_class).to eq(SolidusAdvancedPricing::PricingOptions)
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/spree/variant_pricing_spec.rb
```

Expected: FAIL — the class is still `Spree::Variant::PriceSelector`.

- [ ] **Step 3: Write the initializer template**

Create `lib/generators/solidus_advanced_pricing/install/templates/initializer.rb`:

```ruby
# frozen_string_literal: true

Spree::Config.variant_price_selector_class = 'SolidusAdvancedPricing::PriceSelector'

# Seconds of granularity for the time component of pricing cache keys.
# Set to 0 to omit time from the key entirely.
# Spree::Config.advanced_pricing_cache_granularity = 60
```

- [ ] **Step 4: Set it in the test suite**

In `spec/spec_helper.rb`, inside the `RSpec.configure` block:

```ruby
  config.before(:suite) do
    Spree::Config.variant_price_selector_class = 'SolidusAdvancedPricing::PriceSelector'
  end
```

- [ ] **Step 5: Run the test**

```bash
bundle exec rspec spec/models/spree/variant_pricing_spec.rb
```

Expected: PASS, 2 examples.

- [ ] **Step 6: Run the whole suite**

```bash
bundle exec rspec
```

Expected: all green. If `price_for_options` specs now behave differently, that is the point — investigate any failure before continuing.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: register the advanced price selector"
```

---

## Phase 5 — Integration

### Task 16: Override Variant.with_prices

**Files:**
- Create: `app/decorators/models/solidus_advanced_pricing/spree/variant_decorator.rb`
- Test: `spec/models/spree/variant_with_prices_spec.rb`

Core's `with_prices` checks only currency and country, so a variant whose only price expired yesterday still counts as purchasable in listings.

- [ ] **Step 1: Write the failing test**

Create `spec/models/spree/variant_with_prices_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Variant, '.with_prices' do
  let(:now) { Time.zone.parse('2026-06-15 12:00:00') }
  let(:wholesale_role) { create(:role, name: 'wholesale') }

  def options(**overrides)
    SolidusAdvancedPricing::PricingOptions.new(
      { currency: 'USD', country_iso: nil, at: now, customer_role_ids: [] }.merge(overrides)
    )
  end

  it 'excludes a variant whose only price has expired' do
    variant = create(:variant, price: 100)
    variant.prices.each { |price| price.update!(valid_to: now - 1.day) }
    expect(described_class.with_prices(options)).not_to include(variant)
  end

  it 'includes a variant with an open-ended price' do
    variant = create(:variant, price: 100)
    expect(described_class.with_prices(options)).to include(variant)
  end

  it 'excludes a variant priced only for a role the customer lacks' do
    variant = create(:variant, price: 100)
    variant.prices.each { |price| price.update!(role: wholesale_role) }
    expect(described_class.with_prices(options)).not_to include(variant)
  end

  it 'includes that variant for a customer holding the role' do
    variant = create(:variant, price: 100)
    variant.prices.each { |price| price.update!(role: wholesale_role) }
    expect(
      described_class.with_prices(options(customer_role_ids: [wholesale_role.id]))
    ).to include(variant)
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/spree/variant_with_prices_spec.rb
```

Expected: FAIL — the expired variant is still included.

- [ ] **Step 3: Write the decorator**

Create `app/decorators/models/solidus_advanced_pricing/spree/variant_decorator.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module VariantDecorator
      def self.prepended(base)
        base.singleton_class.prepend(ClassMethods)
      end

      module ClassMethods
        # Core checks only currency and country, so an expired or role-targeted
        # price still makes a variant look purchasable in listings.
        def with_prices(pricing_options = ::Spree::Config.default_pricing_options)
          relation = ::Spree::Price
            .where(::Spree::Variant.arel_table[:id].eq(::Spree::Price.arel_table[:variant_id]))
            .where(currency: pricing_options.currency)
            .where(country_iso: [pricing_options.country_iso, nil].uniq)

          if pricing_options.respond_to?(:at)
            relation = relation.valid_at(pricing_options.at) if pricing_options.at
          end

          if pricing_options.respond_to?(:customer_role_ids)
            relation = relation.visible_to_roles(pricing_options.customer_role_ids)
          end

          where(relation.arel.exists)
        end
      end

      ::Spree::Variant.prepend self
    end
  end
end
```

The `respond_to?` guards keep the override safe if a store passes a plain `Spree::Variant::PricingOptions`.

- [ ] **Step 4: Run the test**

```bash
bundle exec rspec spec/models/spree/variant_with_prices_spec.rb
```

Expected: PASS, 4 examples.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: filter Variant.with_prices by validity window and role"
```

### Task 17: Pin the backward-compatibility guarantee

**Files:**
- Test: `spec/models/spree/backward_compatibility_spec.rb`

This is the spec's central promise: a store with no typed, windowed or targeted prices behaves exactly like core. It must fail loudly if broken.

- [ ] **Step 1: Write the test**

Create `spec/models/spree/backward_compatibility_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'backward compatibility with core pricing' do
  let(:variant) { create(:variant, price: 100) }

  it 'returns the base price as the default price' do
    expect(variant.default_price.amount).to eq(100)
  end

  it 'still answers #price' do
    expect(variant.price).to eq(100)
  end

  it 'reports having a default price' do
    expect(variant).to have_default_price
  end

  it 'builds a default price with the default type and no role' do
    fresh = build(:variant)
    fresh.prices.destroy_all
    built = fresh.default_price_or_build
    expect(built.role_id).to be_nil
    expect(built.price_type_id).to eq(SolidusAdvancedPricing::PriceType.find_by(code: 'default').id)
  end

  it 'shows the admin the untargeted price, not a cheaper role-targeted one' do
    wholesale_role = create(:role, name: 'wholesale')
    create(:price, variant: variant, amount: 60, role: wholesale_role)
    expect(variant.reload.default_price.amount).to eq(100)
  end

  it 'shows the admin the base type, not a cheaper sale price' do
    sale_type = SolidusAdvancedPricing::PriceType.find_by(code: 'sale')
    create(:price, variant: variant, amount: 70, price_type: sale_type)
    expect(variant.reload.default_price.amount).to eq(100)
  end

  it 'prices a line item through the advanced options' do
    order = create(:order_with_line_items, line_items_count: 1)
    expect(order.line_items.first.price).to be_present
  end
end
```

- [ ] **Step 2: Run it**

```bash
bundle exec rspec spec/models/spree/backward_compatibility_spec.rb
```

Expected: PASS, 7 examples. Any failure here means the default-attribute pinning from Task 10 is wrong — fix the implementation, never the test.

- [ ] **Step 3: Run the whole suite**

```bash
bundle exec rspec
```

Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: pin the core backward-compatibility guarantee"
```

---

## Phase 6 — Legacy backend

### Task 18: Add the advanced fields to the price form

**Files:**
- Create: `lib/views/backend/spree/admin/prices/_advanced_fields.html.erb`
- Create: `app/overrides/spree/admin/prices/_form/add_advanced_fields.html.erb.deface`
- Test: `spec/features/admin/price_form_spec.rb`

- [ ] **Step 1: Write the failing feature spec**

Create `spec/features/admin/price_form_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.feature 'editing a price in the admin', :js do
  stub_authorization!

  let!(:wholesale_role) { create(:role, name: 'wholesale') }
  let(:product) { create(:product, price: 100) }
  let(:price) { product.master.default_price }

  scenario 'setting a type, role, window and notes' do
    visit spree.edit_admin_product_price_path(product, price)

    select 'Wholesale', from: 'price_price_type_id'
    select 'wholesale', from: 'price_role_id'
    fill_in 'price_admin_notes', with: 'Labor Day Sale 2026'
    click_button 'Update'

    price.reload
    expect(price.price_type.code).to eq('wholesale')
    expect(price.role).to eq(wholesale_role)
    expect(price.admin_notes).to eq('Labor Day Sale 2026')
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/features/admin/price_form_spec.rb
```

Expected: FAIL — Capybara cannot find `price_price_type_id`.

- [ ] **Step 3: Write the partial**

Create `lib/views/backend/spree/admin/prices/_advanced_fields.html.erb`:

```erb
<div data-hook="admin_product_price_advanced_fields">
  <div class="col-4">
    <%= f.field_container :price_type do %>
      <%= f.label :price_type_id, SolidusAdvancedPricing::PriceType.model_name.human %>
      <%= f.collection_select :price_type_id,
                              SolidusAdvancedPricing::PriceType.ordered,
                              :id, :name,
                              {},
                              { class: 'custom-select fullwidth' } %>
    <% end %>
  </div>

  <div class="col-4">
    <%= f.field_container :role do %>
      <%= f.label :role_id, Spree::Role.model_name.human %>
      <%= f.collection_select :role_id,
                              Spree::Role.order(:name),
                              :id, :name,
                              { include_blank: t('solidus_advanced_pricing.all_customers') },
                              { class: 'custom-select fullwidth' } %>
      <span class="field-hint"><%= t('solidus_advanced_pricing.role_hint') %></span>
    <% end %>
  </div>

  <div class="col-2">
    <%= f.field_container :valid_from do %>
      <%= f.label :valid_from %>
      <%= f.text_field :valid_from, value: f.object.valid_from&.iso8601, class: 'fullwidth datepicker' %>
    <% end %>
  </div>

  <div class="col-2">
    <%= f.field_container :valid_to do %>
      <%= f.label :valid_to %>
      <%= f.text_field :valid_to, value: f.object.valid_to&.iso8601, class: 'fullwidth datepicker' %>
    <% end %>
  </div>

  <div class="col-12">
    <%= f.field_container :admin_notes do %>
      <%= f.label :admin_notes %>
      <%= f.text_area :admin_notes, rows: 2, class: 'fullwidth' %>
      <span class="field-hint"><%= t('solidus_advanced_pricing.admin_notes_hint') %></span>
    <% end %>
  </div>
</div>
```

- [ ] **Step 4: Write the Deface override**

Create `app/overrides/spree/admin/prices/_form/add_advanced_fields.html.erb.deface`:

```erb
<!-- insert_bottom "[data-hook='admin_product_price_form']" -->
<%= render 'spree/admin/prices/advanced_fields', f: f %>
```

- [ ] **Step 5: Add the translations**

In `config/locales/en.yml` under `en:`:

```yaml
  solidus_advanced_pricing:
    all_customers: "All customers"
    role_hint: "Leave blank for all customers. A price type name alone grants no access control — an employee-only price needs this field set."
    admin_notes_hint: "Internal only. Never shown to customers."
  activerecord:
    models:
      solidus_advanced_pricing/price_type:
        one: "Price Type"
        other: "Price Types"
    attributes:
      spree/price:
        price_type_id: "Price Type"
        role_id: "Visible to role"
        valid_from: "Valid from"
        valid_to: "Valid to"
        admin_notes: "Admin notes"
```

The `role_hint` text is the mitigation for the spec's named hazard: `employee` as a type name hides nothing.

- [ ] **Step 6: Run the test**

```bash
bundle exec rspec spec/features/admin/price_form_spec.rb
```

Expected: PASS, 1 example.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add advanced pricing fields to the legacy admin price form"
```

### Task 19: Show the new fields in the prices table

**Files:**
- Create: `lib/views/backend/spree/admin/prices/_advanced_columns.html.erb`
- Create: `app/overrides/spree/admin/prices/_table/add_advanced_columns.html.erb.deface`
- Test: `spec/features/admin/prices_index_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/features/admin/prices_index_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.feature 'the admin prices index' do
  stub_authorization!

  let!(:wholesale_role) { create(:role, name: 'wholesale') }
  let(:product) { create(:product, price: 100) }

  scenario 'showing type and role for each price' do
    product.master.default_price.update!(
      price_type: SolidusAdvancedPricing::PriceType.find_by(code: 'wholesale'),
      role: wholesale_role
    )

    visit spree.admin_product_prices_path(product)

    expect(page).to have_content('Wholesale')
    expect(page).to have_content('wholesale')
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/features/admin/prices_index_spec.rb
```

Expected: FAIL — "Wholesale" is not on the page.

- [ ] **Step 3: Write the column partial**

Create `lib/views/backend/spree/admin/prices/_advanced_columns.html.erb`:

```erb
<td><%= price.price_type&.name %></td>
<td><%= price.role&.name || t('solidus_advanced_pricing.all_customers') %></td>
<td>
  <% if price.valid_from || price.valid_to %>
    <%= [price.valid_from&.to_date, price.valid_to&.to_date].map { |d| d || '—' }.join(' → ') %>
  <% end %>
</td>
```

- [ ] **Step 4: Write the Deface overrides**

Core's markup puts the actions cell last in both the header row and each body row, so both
overrides insert *before* it. That keeps headers and cells aligned.

Create `app/overrides/spree/admin/prices/_table/add_advanced_headers.html.erb.deface`:

```erb
<!-- insert_before "[data-hook='prices_header'] th.actions" -->
<th><%= SolidusAdvancedPricing::PriceType.model_name.human %></th>
<th><%= Spree::Price.human_attribute_name(:role_id) %></th>
<th><%= t('solidus_advanced_pricing.validity') %></th>
```

Create `app/overrides/spree/admin/prices/_table/add_advanced_columns.html.erb.deface`:

```erb
<!-- insert_before "[data-hook='prices_row'] td.actions" -->
<%= render 'spree/admin/prices/advanced_columns', price: price %>
```

Add to `config/locales/en.yml` under `solidus_advanced_pricing:`:

```yaml
    validity: "Validity"
```

Verify alignment visually once the feature spec passes — Deface selectors are the most
version-sensitive part of this plan. `_master_variant_table.html.erb` uses the same hooks, so
check that table too.

- [ ] **Step 5: Run the test**

```bash
bundle exec rspec spec/features/admin/prices_index_spec.rb
```

Expected: PASS, 1 example.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: show price type, role and validity in the admin prices table"
```

### Task 20: Price types CRUD in the legacy backend

**Files:**
- Create: `lib/controllers/backend/spree/admin/price_types_controller.rb`
- Create: `lib/views/backend/spree/admin/price_types/{index,new,edit,_form}.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/features/admin/price_types_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/features/admin/price_types_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.feature 'managing price types' do
  stub_authorization!

  scenario 'listing the seeded types' do
    visit spree.admin_price_types_path
    expect(page).to have_content('Wholesale')
    expect(page).to have_content('Clearance')
  end

  scenario 'creating a type' do
    visit spree.new_admin_price_type_path
    fill_in 'price_type_name', with: 'Dealer'
    fill_in 'price_type_code', with: 'dealer'
    click_button 'Create'

    expect(SolidusAdvancedPricing::PriceType.find_by(code: 'dealer')).to be_present
  end

  scenario 'cannot delete the default type' do
    default_type = SolidusAdvancedPricing::PriceType.find_by(code: 'default')
    expect(default_type.discard).to be(false)
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/features/admin/price_types_spec.rb
```

Expected: FAIL — `undefined method 'admin_price_types_path'`.

- [ ] **Step 3: Add the route**

Replace `config/routes.rb`:

```ruby
# frozen_string_literal: true

Spree::Core::Engine.routes.draw do
  namespace :admin do
    resources :price_types, except: [:show]
  end
end
```

- [ ] **Step 4: Write the controller**

Create `lib/controllers/backend/spree/admin/price_types_controller.rb`:

```ruby
# frozen_string_literal: true

module Spree
  module Admin
    class PriceTypesController < ResourceController
      private

      def model_class
        SolidusAdvancedPricing::PriceType
      end

      def collection
        @collection ||= model_class.ordered
      end

      def permitted_resource_params
        params.require(:price_type).permit(:name, :code, :position, :default)
      end
    end
  end
end
```

- [ ] **Step 5: Write the views**

Create `lib/views/backend/spree/admin/price_types/index.html.erb`:

```erb
<% admin_breadcrumb(plural_resource_name(SolidusAdvancedPricing::PriceType)) %>

<% content_for :page_actions do %>
  <li>
    <%= link_to t('spree.actions.new'), spree.new_admin_price_type_path, class: 'btn btn-primary' %>
  </li>
<% end %>

<table class="index">
  <thead>
    <tr>
      <th><%= SolidusAdvancedPricing::PriceType.human_attribute_name(:name) %></th>
      <th><%= SolidusAdvancedPricing::PriceType.human_attribute_name(:code) %></th>
      <th><%= SolidusAdvancedPricing::PriceType.human_attribute_name(:position) %></th>
      <th><%= SolidusAdvancedPricing::PriceType.human_attribute_name(:default) %></th>
      <th class="actions"></th>
    </tr>
  </thead>
  <tbody>
    <% @collection.each do |price_type| %>
      <tr id="<%= spree_dom_id price_type %>">
        <td><%= price_type.name %></td>
        <td><%= price_type.code %></td>
        <td><%= price_type.position %></td>
        <td><%= price_type.default? ? t('spree.say_yes') : t('spree.say_no') %></td>
        <td class="actions">
          <%= link_to_edit price_type, no_text: true %>
          <%= link_to_delete price_type, no_text: true unless price_type.default? %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

Create `lib/views/backend/spree/admin/price_types/_form.html.erb`:

```erb
<div class="row">
  <div class="col-6">
    <%= f.field_container :name do %>
      <%= f.label :name %>
      <%= f.text_field :name, class: 'fullwidth' %>
    <% end %>
  </div>
  <div class="col-6">
    <%= f.field_container :code do %>
      <%= f.label :code %>
      <%= f.text_field :code, class: 'fullwidth' %>
    <% end %>
  </div>
  <div class="col-6">
    <%= f.field_container :position do %>
      <%= f.label :position %>
      <%= f.number_field :position, class: 'fullwidth' %>
    <% end %>
  </div>
  <div class="col-6">
    <%= f.field_container :default do %>
      <%= f.label :default %>
      <%= f.check_box :default %>
    <% end %>
  </div>
</div>
```

Create `lib/views/backend/spree/admin/price_types/new.html.erb`:

```erb
<% admin_breadcrumb(link_to plural_resource_name(SolidusAdvancedPricing::PriceType), spree.admin_price_types_path) %>
<% admin_breadcrumb(t('spree.actions.new')) %>

<%= form_for [:admin, @price_type] do |f| %>
  <fieldset class="no-border-top">
    <%= render 'form', f: f %>
    <%= render 'spree/admin/shared/new_resource_links' %>
  </fieldset>
<% end %>
```

Create `lib/views/backend/spree/admin/price_types/edit.html.erb`:

```erb
<% admin_breadcrumb(link_to plural_resource_name(SolidusAdvancedPricing::PriceType), spree.admin_price_types_path) %>
<% admin_breadcrumb(@price_type.name) %>

<%= form_for [:admin, @price_type] do |f| %>
  <fieldset class="no-border-top">
    <%= render 'form', f: f %>
    <%= render 'spree/admin/shared/edit_resource_links' %>
  </fieldset>
<% end %>
```

- [ ] **Step 6: Run the test**

```bash
bundle exec rspec spec/features/admin/price_types_spec.rb
```

Expected: PASS, 3 examples.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add price types CRUD to the legacy backend"
```

---

## Phase 7 — solidus_admin

### Task 21: Price types index for solidus_admin

**Files:**
- Create: `lib/controllers/admin/solidus_admin/price_types_controller.rb`
- Create: `lib/components/admin/solidus_admin/price_types/index/component.rb`
- Create: `lib/components/admin/solidus_admin/price_types/index/component.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/features/admin/solidus_admin_price_types_spec.rb`

Read `admin/app/controllers/solidus_admin/adjustment_reasons_controller.rb` and
`admin/app/components/solidus_admin/adjustment_reasons/index/component.rb` in the Solidus
checkout before starting — this task mirrors them.

- [ ] **Step 1: Write the failing test**

Create `spec/features/admin/solidus_admin_price_types_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.feature 'price types in the new admin' do
  stub_authorization!

  before do
    skip 'solidus_admin not available' unless SolidusSupport.admin_available?
  end

  scenario 'listing the seeded types' do
    visit '/admin/price_types'
    expect(page).to have_content('Wholesale')
    expect(page).to have_content('Clearance')
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/features/admin/solidus_admin_price_types_spec.rb
```

Expected: FAIL — routing error for `/admin/price_types`, or skipped if solidus_admin is absent. If skipped, add `solidus_admin` to the gemspec development dependencies and re-run `bin/rake extension:test_app`.

- [ ] **Step 3: Add the route**

Append to `config/routes.rb`, outside the `Spree::Core::Engine` block:

```ruby
if defined?(SolidusAdmin::Engine)
  SolidusAdmin::Engine.routes.draw do
    admin_resources :price_types, except: [:show]
  end
end
```

- [ ] **Step 4: Write the controller**

Create `lib/controllers/admin/solidus_admin/price_types_controller.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdmin
  class PriceTypesController < SolidusAdmin::ResourcesController
    private

    def resource_class = SolidusAdvancedPricing::PriceType

    def permitted_resource_params
      params.require(:price_type).permit(:name, :code, :position, :default)
    end
  end
end
```

- [ ] **Step 5: Write the index component**

Create `lib/components/admin/solidus_admin/price_types/index/component.rb`:

```ruby
# frozen_string_literal: true

class SolidusAdmin::PriceTypes::Index::Component < SolidusAdmin::UI::Pages::Index::Component
  def model_class
    SolidusAdvancedPricing::PriceType
  end

  def search_url
    solidus_admin.price_types_path
  end

  def search_key
    :name_or_code_cont
  end

  def row_url(price_type)
    solidus_admin.edit_price_type_path(price_type)
  end

  def columns
    [
      {
        header: :name,
        data: ->(price_type) { price_type.name }
      },
      {
        header: :code,
        data: ->(price_type) { price_type.code }
      },
      {
        header: :position,
        data: ->(price_type) { price_type.position.to_s }
      },
      {
        header: :default,
        data: ->(price_type) { price_type.default? ? '✓' : '' }
      }
    ]
  end
end
```

If `SolidusAdmin::UI::Pages::Index::Component` does not exist in the Solidus version under test, inherit from the same base class `SolidusAdmin::AdjustmentReasons::Index::Component` uses and mirror its method set exactly.

Create `lib/components/admin/solidus_admin/price_types/index/component.html.erb`:

```erb
<%= render component('ui/pages/index').new(**page_component_attributes) %>
```

- [ ] **Step 6: Run the test**

```bash
bundle exec rspec spec/features/admin/solidus_admin_price_types_spec.rb
```

Expected: PASS, 1 example.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add price types index to solidus_admin"
```

---

## Phase 8 — API

### Task 22: Serialize prices

**Files:**
- Create: `lib/views/api/spree/api/prices/_price.json.jbuilder`
- Create: `lib/views/api/spree/api/prices/{index,show}.json.jbuilder`
- Create: `lib/controllers/api/spree/api/prices_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/spree/api/prices_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/requests/spree/api/prices_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Prices API' do
  let!(:variant) { create(:variant, price: 100) }
  let(:admin) { create(:admin_user) }
  let(:customer) { create(:user) }

  describe 'GET /api/variants/:variant_id/prices' do
    it 'lists prices with their advanced attributes' do
      get "/api/variants/#{variant.id}/prices", headers: { 'Authorization' => "Bearer #{admin.spree_api_key}" }

      expect(response).to have_http_status(:ok)
      price = JSON.parse(response.body)['prices'].first
      expect(price).to include('price_type_code', 'role_id', 'valid_from', 'valid_to')
      expect(price['price_type_code']).to eq('default')
    end

    it 'includes admin_notes for a user who can update the price' do
      variant.default_price.update!(admin_notes: 'Overstock Sale of 2012')
      get "/api/variants/#{variant.id}/prices", headers: { 'Authorization' => "Bearer #{admin.spree_api_key}" }

      price = JSON.parse(response.body)['prices'].first
      expect(price['admin_notes']).to eq('Overstock Sale of 2012')
    end

    it 'omits admin_notes for a non-admin' do
      variant.default_price.update!(admin_notes: 'Overstock Sale of 2012')
      get "/api/variants/#{variant.id}/prices", headers: { 'Authorization' => "Bearer #{customer.spree_api_key}" }

      if response.status == 200
        price = JSON.parse(response.body)['prices'].first
        expect(price).not_to have_key('admin_notes')
      else
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/requests/spree/api/prices_spec.rb
```

Expected: FAIL — routing error.

- [ ] **Step 3: Add the route**

Inside the `Spree::Core::Engine.routes.draw` block in `config/routes.rb`, above the `namespace :admin`:

```ruby
  namespace :api, defaults: { format: 'json' } do
    resources :variants, only: [] do
      resources :prices, only: [:index, :show]
    end
  end
```

- [ ] **Step 4: Write the controller**

Create `lib/controllers/api/spree/api/prices_controller.rb`:

```ruby
# frozen_string_literal: true

module Spree
  module Api
    class PricesController < Spree::Api::BaseController
      def index
        authorize! :index, Spree::Price
        @prices = scope.order(:id)
        respond_with(@prices)
      end

      def show
        @price = scope.find(params[:id])
        authorize! :show, @price
        respond_with(@price)
      end

      private

      def scope
        variant.prices.accessible_by(current_ability, :index)
      end

      def variant
        @variant ||= Spree::Variant.find(params[:variant_id])
      end
    end
  end
end
```

The controller never calls `current_pricing_options` — core builds those `from_context`, which
reads `current_spree_user`, so on an admin-token request it would filter storefront prices by the
admin's own roles.

- [ ] **Step 5: Write the jbuilder views**

Create `lib/views/api/spree/api/prices/_price.json.jbuilder`:

```ruby
json.(price, :id, :variant_id, :amount, :currency, :country_iso, :role_id, :valid_from, :valid_to)
json.display_amount price.display_amount.to_s
json.price_type_code price.price_type&.code
json.price_type_name price.price_type&.name

if can?(:update, price)
  json.admin_notes price.admin_notes
end
```

Create `lib/views/api/spree/api/prices/index.json.jbuilder`:

```ruby
json.prices(@prices) do |price|
  json.partial!('spree/api/prices/price', price: price)
end
```

Create `lib/views/api/spree/api/prices/show.json.jbuilder`:

```ruby
json.partial!('spree/api/prices/price', price: @price)
```

- [ ] **Step 6: Run the test**

```bash
bundle exec rspec spec/requests/spree/api/prices_spec.rb
```

Expected: PASS, 3 examples.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: expose prices with advanced attributes over the API"
```

### Task 23: Permit the new attributes on variant writes

**Files:**
- Create: `app/decorators/models/solidus_advanced_pricing/spree/permitted_attributes_decorator.rb`
- Test: `spec/models/spree/permitted_attributes_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/spree/permitted_attributes_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::PermittedAttributes do
  it 'permits the advanced pricing attributes on prices' do
    expect(described_class.price_attributes).to include(
      :price_type_id, :role_id, :valid_from, :valid_to, :admin_notes
    )
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/models/spree/permitted_attributes_spec.rb
```

Expected: FAIL — `undefined method 'price_attributes'` or the list is missing the keys.

- [ ] **Step 3: Write the decorator**

Create `app/decorators/models/solidus_advanced_pricing/spree/permitted_attributes_decorator.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module PermittedAttributesDecorator
      ADVANCED_PRICE_ATTRIBUTES = [
        :price_type_id, :role_id, :valid_from, :valid_to, :admin_notes
      ].freeze

      def self.prepended(base)
        unless base.respond_to?(:price_attributes)
          base.mattr_accessor(:price_attributes) { [:amount, :currency, :country_iso] }
        end

        base.price_attributes |= ADVANCED_PRICE_ATTRIBUTES
      end

      ::Spree::PermittedAttributes.singleton_class.prepend self
    end
  end
end
```

Core does not define `price_attributes`, so this creates it and stores owners get a single place
to extend. The legacy admin uses `permit!` and is unaffected.

- [ ] **Step 4: Run the test**

```bash
bundle exec rspec spec/models/spree/permitted_attributes_spec.rb
```

Expected: PASS, 1 example.

- [ ] **Step 5: Run the whole suite**

```bash
bundle exec rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: permit advanced pricing attributes on prices"
```

---

## Phase 9 — Release prep

### Task 24: Write the install generator

**Files:**
- Modify: `lib/generators/solidus_advanced_pricing/install/install_generator.rb`
- Test: `spec/generators/install_generator_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/generators/install_generator_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'generators/solidus_advanced_pricing/install/install_generator'

RSpec.describe SolidusAdvancedPricing::Generators::InstallGenerator do
  it 'is configured to copy migrations and the initializer' do
    expect(described_class.instance_methods).to include(:copy_initializer, :add_migrations)
  end
end
```

- [ ] **Step 2: Run and watch it fail**

```bash
bundle exec rspec spec/generators/install_generator_spec.rb
```

Expected: FAIL — missing methods.

- [ ] **Step 3: Write the generator**

Replace `lib/generators/solidus_advanced_pricing/install/install_generator.rb`:

```ruby
# frozen_string_literal: true

module SolidusAdvancedPricing
  module Generators
    class InstallGenerator < Rails::Generators::Base
      class_option :auto_run_migrations, type: :boolean, default: false

      source_root File.expand_path('templates', __dir__)

      def copy_initializer
        template 'initializer.rb', 'config/initializers/solidus_advanced_pricing.rb'
      end

      def add_migrations
        run 'bin/rails railties:install:migrations FROM=solidus_advanced_pricing'
      end

      def run_migrations
        run_migrations = options[:auto_run_migrations] || ask(
          'Would you like to run the migrations now? [Y/n]'
        ).in?(['', 'y', 'Y'])

        if run_migrations
          run 'bin/rails db:migrate'
        else
          puts 'Skipping bin/rails db:migrate, don\'t forget to run it!'
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the test**

```bash
bundle exec rspec spec/generators/install_generator_spec.rb
```

Expected: PASS, 1 example.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add the install generator"
```

### Task 25: Write the README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write the README**

Replace `README.md` with:

````markdown
# Solidus Advanced Pricing

Adds price types, validity windows, role targeting, and internal notes to Solidus prices.

## Installation

```bash
bundle add solidus_advanced_pricing
bin/rails generate solidus_advanced_pricing:install
```

The install generator copies an initializer that registers the price selector, copies the
migrations, and offers to run them. The migrations seed five price types and backfill every
existing price onto `default`.

## What it adds

Each `Spree::Price` gains:

| Field | Meaning |
|---|---|
| `price_type` | One of the admin-managed types. Seeded: default, wholesale, sale, clearance, employee |
| `role` | The single `Spree::Role` that may see this price. Blank means everyone, including guests |
| `valid_from` / `valid_to` | Optional window. Blank means open-ended. `valid_to` is exclusive |
| `admin_notes` | Internal commentary. Never rendered to customers |

## ⚠️ A price type name grants no access control

`price_type` and `role` are independent. Setting a price's type to `employee` and leaving
`role` blank publishes that price to everyone. An employee-only price needs **both**:

```ruby
variant.prices.create!(
  amount: 50,
  currency: 'USD',
  price_type: SolidusAdvancedPricing::PriceType.find_by(code: 'employee'),
  role: Spree::Role.find_by(name: 'employee')
)
```

## How a price is chosen

1. **Filter** — currency must match exactly; the validity window must contain the current time;
   the price must be visible to the customer (`role` blank, or the customer holds that role).
2. **Country specificity** — a country-specific price beats the any-country fallback, even when
   the fallback is cheaper. This matches Solidus core.
3. **Cheapest wins** — among what survives, the lowest amount is selected.

Role is *eligibility only*, never specificity. A role-targeted price set **above** the
untargeted price will never apply — a wholesale price of $120 against a retail price of $100
means wholesale customers pay $100.

## Backward compatibility

A store with no typed, windowed or role-targeted prices behaves exactly like Solidus core. The
admin always edits the untargeted, default-type price, because `default_price_attributes` pins
`role_id` to `nil` and `price_type_id` to the default type.

If a variant's only prices all have windows and none is currently valid, `variant.price` returns
`nil` — the same thing core does when no price matches. Keep one open-ended base price per
variant.

## Caching

Pricing cache keys include the customer's pricing-relevant roles and a coarse time bucket.
Without the role component, a wholesale price would be cached and served to guests.

```ruby
# Seconds. 0 disables the time component entirely.
Spree::Config.advanced_pricing_cache_granularity = 60
```

A price transition can be up to one bucket late in cached views.

## Relationship to promotions

This gem is for prices that *are* a different amount — wholesale tiers, price lists, scheduled
rollovers. For discounts off a price, including codes, usage limits and stacking, use
`solidus_promotions`. A windowed `sale` price here is fine; promotion machinery is not
reimplemented.

## Development

```bash
bin/rake extension:test_app
bundle exec rspec
```
````

- [ ] **Step 2: Run the full suite one more time**

```bash
bundle exec rspec
```

Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: write the README"
```

---

## Self-review notes

**Spec coverage.** Every section of the design spec maps to a task: price types (3–6), seeded
types (5), columns and backfill (7), validations (8), scopes (9), pricing options and the
tri-state removal (10), cache granularity (11), cache key (12), selector (13–14), registration
(15), `with_prices` (16), backward compatibility (17), legacy admin (18–20), solidus_admin (21),
API and the `admin_notes` boundary (22–23), install generator (24), README including the
type-vs-role hazard (25).

**Known deviations from the spec, to fold back into the spec document:**

1. Cache granularity disables at `0`, not `nil` — an integer preference coerces `nil` to `0`.
2. `Spree::PermittedAttributes.price_attributes` does not exist in core; Task 23 creates it.

**Risk flags for the implementer:**

- Task 19's Deface column alignment is the least certain step in the plan; verify visually.
- Task 21 depends on solidus_admin component base classes that differ across 4.3–4.8. Read the
  upstream `adjustment_reasons` components in the Solidus version you are testing against before
  writing the component, and mirror them.
