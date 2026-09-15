# solidus_advanced_pricing — Design

Status: FINAL (approved design, ready for implementation planning)
Date: 2026-09-14

## Problem

Solidus core models a price as `(variant, currency, country_iso, amount)`. There is no way to
express that a price is a particular *kind* of price, that it applies only during a window of
time, or that it applies only to a certain kind of customer.

Stores that need wholesale or dealer pricing, scheduled price-list rollovers, or simply a record
of why a price exists currently reach for promotions. Promotions are the wrong tool for the
first two: they *discount* a price rather than replacing it, which leaks the retail price to a
B2B customer, reads as a discount on invoices, and reports as promotional revenue when it is
not. See the promotions decision below for the full evaluation.

## Goal

A Solidus extension gem adding three things to `Spree::Price`, plus internal commentary:

1. Configurable, admin-managed **price types**
2. An optional **validity window** (`valid_from` / `valid_to`)
3. Optional **role targeting** — one `Spree::Role` a price is visible to
4. **`admin_notes`** — internal-facing commentary on why a price exists

...delivered through Solidus' existing `Spree::Config.variant_price_selector_class` seam rather
than by monkey-patching price lookup.

## Non-goals

- **Time-boxed sale pricing.** That belongs in `solidus_promotions`, which does it better.
- **Role exclusion.** Only inclusion is expressible. "Everyone except employees" requires one
  targeted price per included role.
- **Re-pricing existing line items.** Carts are left alone, matching core.
- **A prices screen in solidus_admin.** Upstream has not built one; this gem will not guess it.
- **Display-only / compare-at price types.** Every price is a selection candidate.

## Architecture

Two subclasses registered in one initializer line. Core delegates `pricing_options_class` from
the selector class, so this wires both:

```ruby
Spree::Config.variant_price_selector_class = "SolidusAdvancedPricing::PriceSelector"
```

Everything else is additive columns, one new table, view overrides, and an API controller.

## Data model

```
solidus_advanced_pricing_price_types
  id, name, code (unique), position, default (boolean), deleted_at, timestamps

spree_prices                                   (columns added)
  price_type_id  bigint,   NOT NULL, FK → price_types, indexed
  role_id        bigint,   NULL,     FK → spree_roles, indexed
  valid_from     datetime, NULL      (nil = open-ended start)
  valid_to       datetime, NULL      (nil = never expires)
  admin_notes    text,     NULL
  index (variant_id, currency, country_iso, role_id, valid_from, valid_to)
```

`role_id` is modeled on `country_iso`: nullable, where `nil` means "every customer, including
guests". There is no join table and no exclusion.

The install migration seeds a `default` price type (`default: true`) and backfills every
existing price into it before adding the NOT NULL constraint.

## Price selection

`SolidusAdvancedPricing::PricingOptions < Spree::Variant::PricingOptions`

`desired_attributes` gains two real, assignable `Spree::Price` columns:

- `price_type_id` — pinned to the default type in `default_price_attributes`
- `role_id` — pinned to `nil` in `default_price_attributes`

Both must be assignable columns because core calls `prices.build(default_price_attributes)` in
`DefaultPrice#default_price_or_build`. They also make core's public `Spree::Price
.with_default_attributes` scope correct for consumers.

Two contextual readers live *outside* `desired_attributes`, because they are not price columns:

| reader | default | meaning |
|---|---|---|
| `at` | `Time.current` | only prices whose window contains this instant |
| `customer_role_ids` | `[]` | the roles this customer holds; `[]` is a guest |

Built from context as:

- `from_context(ctx)` → `customer_role_ids: ctx.current_spree_user&.role_ids || []`
- `from_line_item(li)` → `customer_role_ids: li.order&.user&.role_ids || []`

`SolidusAdvancedPricing::PriceSelector < Spree::Variant::PriceSelector`

`#price_for_options` runs in memory over `variant.prices`, as core does, so unsaved prices and
preloaded associations keep working. Order of operations:

1. **Filter** — drop discarded (unless the variant itself is discarded, per core); currency must
   match exactly; the window must contain `at`; and the price must be visible:
   `price.role_id.nil? || customer_role_ids.include?(price.role_id)`
2. **Country specificity** — if any survivor matches the desired `country_iso`, keep only those;
   otherwise keep the `country_iso IS NULL` fallback. This preserves core's behavior exactly:
   country is specificity, not competition.
3. **Cheapest wins** — `min_by(&:amount)` across the surviving bucket. Ties break on price type
   `position`, then `updated_at` desc, then `id` desc, mirroring core's ordering.

Role is **eligibility only** (step 1), never specificity. A wholesale customer sees both the
wholesale and the untargeted price and gets whichever is cheaper. A wholesale price set *above*
retail therefore never applies — that is intended and must be documented prominently, since it
is the one genuinely surprising consequence of this model.

The same predicates exist as AR scopes — `valid_at(time)`, `visible_to_roles(ids)`,
`for_price_type(x)` — and `Spree::Variant.with_prices` is overridden in a decorator to use them.
Without that override, a variant whose only price expired yesterday still counts as purchasable
in product listings, because core's `with_prices` checks only currency and country.

## Backward compatibility

The guarantee: **a store with no typed, windowed or targeted prices behaves identically to
core.** This gets an explicit spec that fails loudly, because every other compatibility claim
rests on it.

It holds because the backfill gives every existing price the default type, `role_id` defaults to
`nil` (visible to all), and both window bounds default to `nil` (always valid). Defaulting `at`
to `Time.current` changes nothing for a price with no window.

One consequence to document: if a variant's only base prices all have windows and none is
currently valid, `variant.price` returns `nil`, exactly as core returns `nil` when no price
matches. Stores should keep one open-ended base price per variant.

## Admin surfaces

**Legacy backend.** `spree/admin/prices/_form` and `_table` both carry `data-hook` attributes, so
Deface inserts at `admin_product_price_fields`: a price type select, a role select (mirroring the
existing country select, blank = all customers), `valid_from`/`valid_to` datetime fields, and an
`admin_notes` textarea. The prices index gains type, role and window columns.
`Spree::Admin::ResourceController#permitted_resource_params` calls `permit!`, so the new columns
need no strong-params work.

Plus `Spree::Admin::PriceTypesController` — standard `ResourceController` CRUD.

**solidus_admin.** A price types CRUD only, mirroring the existing `adjustment_reasons` /
`refund_reasons` resource components. Per-variant price management stays in the legacy backend.

## API

Core's API has no prices resource; variants serialize only `price` / `display_price` via
`price_for_options(current_pricing_options)`, which the new selector improves for free.

v1 adds `Spree::Api::PricesController` plus jbuilder views exposing price type, role, validity
window, and `admin_notes`. Two rules:

- **Explicit pricing options, never `current_pricing_options`.** Core builds those
  `from_context`, which reads `current_spree_user` — on an admin-token request that would
  silently filter storefront prices by the *admin's* roles.
- **`admin_notes` is serialized only when `can?(:update, price)`.** It is internal commentary and
  must never reach a storefront payload.

## Caching

`PricingOptions#cache_key` in core joins `desired_attributes` values. Since `customer_role_ids`
and `at` deliberately live outside that hash, an unmodified `cache_key` would render a wholesale
customer's price into a fragment cache and then serve it to guests. The subclass **must**
override `cache_key` to include sorted `customer_role_ids`.

Time is the harder half: keying on raw `at` gives a 0% hit rate, while omitting it serves prices
from cache past their window. v1 ships a coarse bucket —
`Spree::Config.advanced_pricing_cache_granularity`, default 60 seconds — with the trade-off
documented plainly: a price transition can be up to one granularity window late in cached views.
Stores that cannot tolerate that set it to `nil` and lose price-dependent fragment caching.

## Validations and edge cases

- `valid_to` must be after `valid_from` when both are present.
- Price types are soft-deletable. Discarding one removes it from the new-price dropdown but
  leaves historical prices intact and still selectable, so "Overstock Sale of 2012" keeps its
  type forever.
- The `default: true` type is guarded against both discard and having its flag cleared while it
  is the only default.
- `role_id` and `price_type_id` integrity is enforced by foreign keys.

## Testing

- Model and scope specs, including the price type default/discard guards.
- Selector specs driven by `ActiveSupport::Testing::TimeHelpers` across window boundaries.
- An explicit backward-compatibility spec asserting `default_pricing_options` behavior is
  unchanged from core.
- A cache-key spec asserting two different role sets never collide.
- Request specs for the API, including the `admin_notes` authorization boundary.
- Feature specs for the legacy backend; component specs for the solidus_admin price types CRUD.
- Factories under `lib/solidus_advanced_pricing/testing_support/factories.rb`, per contrib
  convention.

## Packaging

`solidus_dev_support` skeleton: dummy app, RSpec, RuboCop, CI matrix. The engine uses
`solidus_support`'s `backend_available?` / `admin_available?` / `api_available?` guards to add
engine paths conditionally, so a headless store without `solidus_backend` does not load Deface
overrides it cannot use. Solidus floor is 4.0 (`solidus_admin` exists only from 4.3, hence a
guard rather than a hard dependency).

## Decisions

Every explicit decision from the brainstorm, with rationale.

- **Price types are an admin-managed model**, not a config list or free-form string.
  Rationale: store admins can add types without a deploy, and `position` gives a deterministic
  tie-breaker.
- **v1 ships the full stack**: model + price-selection core, legacy backend admin UI,
  solidus_admin UI, and REST API exposure.
  Rationale: an extension nobody can edit or read over the API isn't usable in a real store.
- **Role targeting uses `Spree::Role`**, not a gem-owned group model or lambda predicates.
  Rationale: works out of the box with solidus_auth_devise and any roles a store already
  defines; keeps targeting queryable in SQL.
- **Public contrib-style gem**: broad Solidus support, solidus_dev_support dummy app, CI matrix,
  README, released to RubyGems.
  Rationale: the feature is generally useful; building to contrib conventions from the start is
  cheaper than retrofitting them.
- **No display-only price types.** Every price is a selection candidate; compare-at/MSRP display
  is the storefront's concern.
  Rationale: keeps the model small; a `sellable` flag can be added later without breaking
  anything.
- **Stale carts are left alone.** A line item keeps its captured price when the source price
  expires or the customer loses a role; the gem does not hook the order updater.
  Rationale: matches core, which never re-prices line items on its own.
- **Additive columns on `spree_prices`** plus a gem-owned price types table, rather than a
  sidecar `price_details` table or a parallel prices table.
  Rationale: the selector stays a single joinable query and eligibility becomes composable AR
  scopes, instead of the LEFT-OUTER-JOIN dance a sidecar would force on every lookup.
- **`price_type_id` is NOT NULL**; the install migration seeds a `default` type and backfills
  every existing price into it.
  Rationale: "every price has a type" is a far easier invariant to hold than "nil is secretly a
  type", and admins see a real name in the UI.
- **Filter first, then cheapest wins.** Currency, window and role visibility narrow the
  candidates; country specificity picks the bucket; the lowest amount wins within it.
  Rationale: core treats country as specificity, not competition — a `nil`-country fallback must
  not undercut a deliberate country-specific price.
- **One `role_id` per price, modeled on `country_iso`** — nullable FK to `spree_roles`, `nil`
  meaning every customer including guests. No join table, no exclusion.
  Rationale: matches how country already works, removes a table and with it an N+1 preloading
  problem, and makes `role_id` a plain indexed column `with_prices` can filter in SQL.
  Cost: "everyone except role X" is no longer expressible.
- **Role is eligibility only, not specificity.** A role match qualifies a customer to see a
  price; among everything visible, cheapest wins after country specificity.
  Rationale: chosen over "role beats country" and "country beats role". Consequence: a
  role-targeted price set above the untargeted price never applies.
- **`price_type_id` and `role_id` are `desired_attributes`; `at` and `customer_role_ids` are
  not.** Rationale: core calls `prices.build(default_price_attributes)`, so every key in that
  hash must be an assignable `Spree::Price` column. The first two are columns; the contextual
  filters are not.
- **`admin_notes` text column on `spree_prices`** for internal commentary ("Labor Day Sale 2025",
  "Overstock Sale of 2012"), never rendered to customers.
  Rationale: makes historical prices legible years after whoever created them left.
- **solidus_admin scope is price types CRUD only.** Per-variant price management stays in the
  legacy backend.
  Rationale: the new admin has no price management at all — `Products::Show` exposes a single
  `f.text_field(:price)` writing through `DefaultPrice`, with no prices index, form or route.
  Building that screen is a larger project than this feature and would guess at a design
  upstream has not landed.
- **The API passes explicit pricing options** rather than inheriting `current_pricing_options`.
  Rationale: core builds those `from_context`, which reads `current_spree_user`; on an
  admin-token request that would silently filter storefront prices by the admin's roles.
- **Promotions were investigated and set aside.** `solidus_promotions` already ships
  `Benefits::AdvertisePrice`, price-level conditions (`PriceProduct` / `PriceTaxon` /
  `PriceOptionValue`), `Conditions::UserRole`, `PricePatch` (`discounts` / `discounted_amount`)
  and `ProductAdvertiser`. Not adopted because: a promotion *discounts* a price rather than
  replacing it (wrong semantics for B2B — it leaks retail and reports as promotional revenue);
  `Conditions::UserRole` implements only `order_eligible?` with `any`/`all` policies, so there
  is no price-level or exclude form; `ProductAdvertiser` is never invoked by Solidus and needs
  an order, which is awkward on catalog pages and for guests; and promotions have no concept of
  a price type at all. Revisit for time-boxed sale pricing, which the promotion engine does
  better.

### Superseded during the brainstorm

Kept so the reasoning trail survives; do not implement these.

- *Role rules in a join table with a `restrict` / `exclude` mode column.* Superseded by the
  single `role_id` column. Exclusion went with it.
- *Contextual filters as tri-state, where `nil` means "ignore this filter".* Superseded once
  role became eligibility-only: `nil` and `[]` became indistinguishable for
  `customer_role_ids`, and an `at` of `nil` would have made an admin lookup pick arbitrarily
  between an expiring price and its replacement. Both now take plain defaults
  (`[]` and `Time.current`).
- *A `priority` column on price types driving selection.* Superseded by cheapest-wins;
  `position` survives as a tie-breaker and admin sort order only.

## Context gathered

- Local Solidus checkout: `4.8.0.dev` (`~/RubymineProjects/solidus`), minimum Rails 7.2.
- Ruby 3.3.10, Bundler 4.0.16.
- Relevant core seams:
  - `Spree::Price` — `core/app/models/spree/price.rb`
  - `Spree::Variant::PricingOptions` — `desired_attributes`, built `from_line_item`,
    `from_price`, `from_context`
  - `Spree::Variant::PriceSelector#price_for_options` — already pluggable
  - `Spree::Config.variant_price_selector_class`, which core delegates
    `pricing_options_class` from
  - `Spree::DefaultPrice` — `default_price` routes through the same selector, and
    `default_price_or_build` calls `prices.build(default_price_attributes)`
  - `Spree::Variant.with_prices` — checks only currency and country; needs overriding
  - `Spree::Role` / `Spree::RoleUser` — `has_many :users, through: :role_users`
