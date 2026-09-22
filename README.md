# Solidus Advanced Pricing

[![CircleCI](https://circleci.com/gh/solidusio-contrib/solidus_advanced_pricing.svg?style=shield)](https://circleci.com/gh/solidusio-contrib/solidus_advanced_pricing)
[![codecov](https://codecov.io/gh/solidusio-contrib/solidus_advanced_pricing/branch/main/graph/badge.svg)](https://codecov.io/gh/solidusio-contrib/solidus_advanced_pricing)

Adds price types, role-targeting, validity windows and admin notes to `Spree::Price`,
so a variant can carry several competing prices — a wholesale tier, a scheduled sale,
an employee price — and have the right one selected automatically.

This gem is for prices that *are* a different amount. See
[Relationship to solidus_promotions](#relationship-to-solidus_promotions) below if what
you actually want is a discount.

## Installation

Add solidus_advanced_pricing to your Gemfile:

```shell
bundle add solidus_advanced_pricing
```

Then run the installation generator:

```shell
bin/rails generate solidus_advanced_pricing:install
```

The generator:

- Copies `config/initializers/solidus_advanced_pricing.rb`, which registers
  `SolidusAdvancedPricing::PriceSelector` as `Spree::Config.variant_price_selector_class`.
  This is what makes pricing type/role/validity-aware; without it the gem's columns exist
  but are never consulted.
- Copies this gem's four migrations into your app.
- Offers to run `bin/rails db:migrate` for you.

Those migrations add the columns described below to `spree_prices`, seed five price
types (`default`, `wholesale`, `sale`, `clearance`, `employee`), and backfill every
existing price row onto the `default` type. Nothing about existing pricing behavior
changes until you start setting the new columns — see
[Backward compatibility](#backward-compatibility).

## What it adds to `Spree::Price`

| Column | Type | Meaning |
|---|---|---|
| `price_type_id` | bigint, not null | Belongs to `SolidusAdvancedPricing::PriceType`. Set automatically to the default type if left blank. |
| `role_id` | integer, nullable | Belongs to `Spree::Role`. `nil` means visible to everyone, including guests. |
| `valid_from` | datetime, nullable | Window opens here. `nil` means always open. |
| `valid_to` | datetime, nullable | Window closes here, **exclusive** — a price is valid up to but not including this instant, so a window ending at midnight and the next one starting at midnight don't both match. `nil` means never closes. |
| `admin_notes` | text, nullable | Internal only. Never shown to customers; see [API](#api) for exactly who can see it. |

`price_type_id` is required and validated with `presence: true`; `role_id`,
`valid_from` and `valid_to` are all optional. `valid_to` must be after `valid_from`
when both are set.

## A price type is not access control

**Setting a price's `price_type` to `employee` does nothing on its own.** Type and
role are independent columns. A price typed `employee` with `role_id` left blank is
visible to every customer, guests included — the name is just a label for the admin
UI and reporting; it grants no eligibility by itself. Two of the five seeded types,
`wholesale` and `employee`, exist specifically to invite this mistake.

If a price should only be available to a specific group, you must **also** set `role`:

```ruby
employee_role = Spree::Role.find_or_create_by!(name: "employee")
employee_type = SolidusAdvancedPricing::PriceType.find_by(code: "employee")

variant.prices.create!(
  amount: 45,
  currency: "USD",
  price_type: employee_type,
  role: employee_role
)
```

With both fields set, a guest or any customer without the `employee` role still sees
the ordinary price; only a customer holding that role sees $45.

## How a price is chosen

For a given variant, currency, and requesting customer, `PriceSelector` picks a price
in three steps:

1. **Filter.** A price survives only if: its currency matches exactly; the current
   time falls inside its validity window (or it has none); and it's visible to the
   customer — `role_id` is blank, or the customer holds that role. If a price type is
   pinned (see [Admin vs. customer lookups](#admin-vs-customer-lookups) below),
   non-matching types are dropped here too.
2. **Country specificity.** Among what survives, a price matching the customer's
   country beats every country-agnostic (`country_iso: nil`) price — **even when the
   agnostic price is cheaper.** This matches core Solidus behavior.
3. **Cheapest wins.** Within the winning country bucket, the lowest `amount` is
   selected. Ties are broken by price type position (lower `position` wins), then by
   most recently updated, then by highest id.

### Role is eligibility, never specificity

A role only decides *whether* a price is a candidate, never how strongly it competes
once it is one. A role-targeted price set **above** the untargeted price will never
apply, because step 3 always takes the cheapest survivor:

```
Retail (no role):     $100
Wholesale (wholesale): $120
```

A wholesale customer still pays $100 — their role makes the $120 price *eligible*,
but the untargeted $100 price is cheaper and wins. This is intended, and it's the one
genuinely surprising consequence of the design: if you want a role to guarantee a
better price, that price has to actually be cheaper than what an untargeted customer
would pay.

### Admin vs. customer lookups

`SolidusAdvancedPricing::PricingOptions.default_price_attributes` pins
`price_type_id` to the default type and `role_id` to `nil`. This is what
`Spree::Variant#default_price_or_build` and the admin price form build against, so an
admin always edits the base (`default`-typed, untargeted) price rather than
accidentally landing on a cheaper sale or wholesale row.

Customer-facing lookups (`PricingOptions.from_line_item`, `.from_context`) clear that
pin — `price_type_id` is `nil`, meaning every type competes — and populate
`customer_role_ids` from the current user's roles, so the full set of eligible prices
is considered.

## Backward compatibility

A store with no typed, windowed, or role-targeted prices — i.e. one that has only run
the migrations and never set the new columns beyond their defaults — behaves exactly
like core Solidus. This is pinned by
[`spec/models/spree/backward_compatibility_spec.rb`](spec/models/spree/backward_compatibility_spec.rb).

One real consequence to be aware of: if a variant's *only* prices all have validity
windows and none is currently open, `variant.price` returns `nil` — the same thing
core does when no price matches at all, not an error. Keep at least one open-ended
(`valid_from`/`valid_to` both blank) base price per variant if you don't want a
variant to become unpriced outside its scheduled windows.

## Caching

Pricing lookups are cached, and the cache key includes:

- the attributes core already keys on (currency, country, etc.)
- the customer's *pricing-relevant* roles
- a coarse time bucket

The role component is mandatory, not optional: without it, the first customer to
resolve a variant's price — guest or not — would have that price cached and served to
everyone else who hits the same key, including a guest being served a role-gated
wholesale price.

Roles are narrowed to only those roles that some price actually references
(`SolidusAdvancedPricing::PriceTypeCache.pricing_role_ids`), not the customer's full
role list. This keeps cache key cardinality low without affecting which price is
selected.

The time bucket width is controlled by:

```ruby
Spree::Config.advanced_pricing_cache_granularity = 60 # seconds, default
```

Setting it to `0` disables the time component of the cache key entirely. This trades
a slightly more precise validity boundary for cheaper caching: a price whose window
just closed can keep being served from cache until something else invalidates the
key. The default of 60 seconds bounds how stale a validity-window transition can be.

## Admin

**Legacy backend** (`solidus_backend`) gets the full experience:

- The price form gains price type, role, validity (`valid_from`/`valid_to`), and
  admin notes fields, added via Deface overrides
  (`app/overrides/spree/admin/prices/_form/add_advanced_fields.html.erb.deface`).
- The prices tables (both the single-variant and master-variant listings) gain
  columns for type, role, and validity.
- Price types get full CRUD at `/admin/price_types` (`spree.admin_price_types_path`).
  This gem does not hook the admin configurations menu, so there is no sidebar link
  to it — link to it yourself, or navigate there directly.

**solidus_admin** gets a **price types index only**
(`SolidusAdmin::PriceTypes::Index::Component`, at `solidus_admin.price_types_path`).
Its rows link back to the legacy backend for edit/new; per-variant price management
stays entirely in the legacy backend. This is deliberate: upstream Solidus's new
admin has no prices screen of its own yet, and building one here would mean guessing
at a design that hasn't landed upstream. Be aware that this component is built
against pre-1.0 `solidus_admin` internals (`SolidusAdmin::UI::Pages::Index::Component`,
`SolidusAdmin::ResourcesController`) and may need updating when you upgrade
`solidus_admin`.

## API

```
GET /api/variants/:variant_id/prices
GET /api/variants/:variant_id/prices/:id
```

Each price is serialized with its advanced attributes — `price_type_code`,
`price_type_name`, `role_id`, `valid_from`, `valid_to` — and `admin_notes` is included
only for a caller who can update that price.

**This endpoint is admin-facing.** Core's `DefaultCustomer` permission set (what every
non-admin API token gets) grants no rights on `Spree::Price` at all, so a non-admin
token receives `401 Unauthorized` on the whole endpoint, not a filtered response.
Headless storefronts do not need this endpoint for normal pricing: core's variants
endpoint already serializes `price` and `display_price` through this gem's selector
automatically, because the selector is registered globally via
`Spree::Config.variant_price_selector_class`.

## Known limitations

- **Search and taxon filtering ignore validity windows.** `search_arguments`
  (`SolidusAdvancedPricing::PricingOptions#search_arguments`), which core's product
  search and taxon filtering query directly, is a plain equality hash passed to
  `Spree::Price.where(...)`. It can express type and role but has no way to express
  "and the validity window contains now." A variant whose only price expired
  yesterday can still appear in search results, even though
  `Spree::Variant#price_for_options` correctly returns `nil` for it and
  `Spree::Variant.with_prices` (used by listings that call it directly) correctly
  excludes it. Closing this gap would require overriding the two core search call
  sites as well, which this gem does not currently do.
- **No role exclusion.** Only inclusion is expressible via `role_id`. "Everyone
  except employees" cannot be written directly — approximate it with one targeted
  price per role you *do* want to include.
- **One role per price.** `role_id` targets a single `Spree::Role`. A customer may
  hold several roles and will see every price targeted at any role they hold (the
  cheapest of them wins, per [how a price is chosen](#how-a-price-is-chosen)) — but a
  single price row can't itself target more than one role.
- **The default price type id is memoized per process**
  (`SolidusAdvancedPricing::PriceTypeCache.default_id`). If an admin changes which
  type is marked default, other web and worker processes keep using the old default
  until they restart, because the cache is only cleared by callbacks running in the
  same process that made the change.

## Relationship to solidus_promotions

This gem is for prices that genuinely *are* a different amount for a given customer
or window: wholesale tiers, price lists, a scheduled rollover to a sale price. It
does not reimplement promotion machinery — no codes, no usage limits, no stacking
rules. A `sale`-typed price with a validity window is a perfectly good way to model a
time-boxed sale here.

For discounting an existing price — percentage or fixed-amount off, promo codes,
usage limits, stacking behavior — use
[`solidus_promotions`](https://github.com/solidusio/solidus_promotions) instead.
`solidus_promotions` does ship `Benefits::AdvertisePrice` and price-level conditions,
and it can look similar to what this gem does on the surface, but a promotion
*discounts* a price rather than replacing it. For B2B-style pricing that is the wrong
semantics: the retail price still leaks (it's the "was" price the discount is
computed from), and the sale reports as promotional revenue rather than as the
customer's actual price. Use this gem when the price itself should simply be
different for that customer or window.

## Development

```shell
bin/rake extension:test_app
bundle exec rspec
```

To run [Rubocop](https://github.com/bbatsov/rubocop) static code analysis run

```shell
bundle exec rubocop
```

When testing your application's integration with this extension you may use its factories.
You can load Solidus core factories along with this extension's factories using this statement:

```ruby
SolidusDevSupport::TestingSupport::Factories.load_for(SolidusAdvancedPricing::Engine)
```

### Running the sandbox

To run this extension in a sandboxed Solidus application, you can run `bin/sandbox`. The path for
the sandbox app is `./sandbox` and `bin/rails` will forward any Rails commands to
`sandbox/bin/rails`.

Here's an example:

```
$ bin/rails server
=> Booting Puma
=> Rails 6.0.2.1 application starting in development
* Listening on tcp://127.0.0.1:3000
Use Ctrl-C to stop
```

### Releasing new versions

Please refer to the [dedicated page](https://github.com/solidusio/solidus/wiki/How-to-release-extensions) in the Solidus wiki.

## License

Copyright (c) 2026 Patrick McMorran, released under the New BSD License.
