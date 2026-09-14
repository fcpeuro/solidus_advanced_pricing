# solidus_advanced_pricing — Design

Status: DRAFT (brainstorm in progress)

## Problem

Solidus core models a price as `(variant, currency, country_iso, amount)`. There is no way to
express that a price is a particular *kind* of price, that it only applies during a window of
time, or that it applies only to (or never to) certain kinds of customer. Stores that need
wholesale tiers, timed sale pricing, or MSRP/compare-at values currently reach for promotions,
which are the wrong tool: promotions are order-level adjustments, not variant prices.

## Goal

A Solidus extension gem that adds to prices:

1. Configurable, admin-managed **price types**
2. Optional **validity window** (`valid_from` / `valid_to`)
3. **Role-based targeting** — restrict a price to a set of roles, or exclude a set of roles

...without forking price lookup, by using Solidus' existing
`Spree::Config.pricing_options_class` / `Spree::Config.variant_price_selector_class` seams.

## Decisions

(appended as they are made during the brainstorm)

- **Price types are an admin-managed model**, not a config list or free-form string.
  Rationale: store admins can add types without a deploy, and a `priority` column on the
  type gives a deterministic tie-breaker when several prices are simultaneously valid.
- **v1 ships the full stack**: model + price-selection core, legacy backend admin UI,
  solidus_admin UI, and REST API exposure.
  Rationale: an extension nobody can edit or read over the API isn't usable in a real store.
- **Role targeting uses `Spree::Role`**, not a gem-owned group model or lambda predicates.
  Rationale: works out of the box with solidus_auth_devise and any roles a store already
  defines; keeps the rules queryable in SQL.
- **Public contrib-style gem**: broad Solidus support, solidus_dev_support dummy app, CI
  matrix, README, released to RubyGems.
  Rationale: the feature is generally useful; building to contrib conventions from the start
  is cheaper than retrofitting them.

- **Lowest amount always wins** among prices that are eligible for the customer, currency and
  country. Rationale: trivial for admins to reason about; targeting is expressed by role rules
  and date windows, not by precedence juggling.
- **No display-only price types.** Every price is a selection candidate; compare-at/MSRP
  display is the storefront's concern. Rationale: keeps the model small; a `sellable` flag can
  be added later without breaking anything.
- **Stale carts are left alone.** A line item keeps its captured price when the source price
  expires or the customer loses a role; the gem does not hook the order updater.
  Rationale: matches core, which never re-prices line items on its own, and keeps this gem out
  of the order lifecycle.

- **Storage approach A**: additive columns on `spree_prices` plus two gem-owned tables
  (price types, price role rules). Rationale: the selector stays a single joinable query and
  eligibility becomes composable AR scopes, instead of the LEFT-OUTER-JOIN dance a sidecar
  table would force on every lookup.
- **Role rules live in one table with a `mode` column** (`restrict` / `exclude`) rather than
  two associations. Rationale: "exclude wins" becomes a single evaluation order, and the admin
  renders one list of rules instead of two pickers.
- **Filter first, then lowest amount wins.** Currency, country specificity, validity window and
  role rules narrow the candidate set; the lowest amount wins *within* the surviving bucket.
  Rationale: core treats country as specificity, not competition — a `nil`-country fallback
  must not undercut a deliberate country-specific price.
- **`price_type_id` is NOT NULL**; the install migration seeds a `default` price type and
  backfills every existing price into it. Rationale: "every price has a type" is a far easier
  invariant to hold than "nil is secretly a type", and admins see a real name in the UI.

- **Contextual filters are tri-state** (`at`, `role_ids`): `nil` means "ignore this filter"
  (administrative lookup), a value means filter by it, and `role_ids: []` means a guest with no
  roles. Rationale: `Spree::Config.default_pricing_options` calls `PricingOptions.new` with no
  arguments, so an unfiltered default keeps every admin lookup byte-identical to core, while a
  guest is still correctly denied role-restricted prices.
- **`at`/`role_ids` are readers on the pricing options, NOT keys in `desired_attributes`.**
  Rationale: core calls `prices.build(default_price_attributes)`, so every key in that hash must
  be an assignable `Spree::Price` column. `price_type_id` qualifies; contextual filters do not.
- **`admin_notes` text column on `spree_prices`** for internal-facing commentary
  ("Labor Day Sale 2025", "Overstock Sale of 2012"). Internal only — never rendered to
  customers. Rationale: makes historical prices legible years after whoever created them left.

## Context gathered

- Local Solidus checkout: `4.8.0.dev` (`~/RubymineProjects/solidus`), min Rails 7.2.
- Ruby 3.3.10, Bundler 4.0.16 on this machine.
- Relevant core seams:
  - `Spree::Price` — `core/app/models/spree/price.rb`
  - `Spree::Variant::PricingOptions` — `desired_attributes` hash, built `from_line_item`,
    `from_price`, `from_context`
  - `Spree::Variant::PriceSelector#price_for_options` — already pluggable
  - `Spree::Config.pricing_options_class`, `Spree::Config.variant_price_selector_class`
  - `Spree::Role` / `Spree::RoleUser` — `has_many :users, through: :role_users`
