# Solidus Advanced Pricing

[![CircleCI](https://circleci.com/gh/solidusio-contrib/solidus_advanced_pricing.svg?style=shield)](https://circleci.com/gh/solidusio-contrib/solidus_advanced_pricing)
[![codecov](https://codecov.io/gh/solidusio-contrib/solidus_advanced_pricing/branch/main/graph/badge.svg)](https://codecov.io/gh/solidusio-contrib/solidus_advanced_pricing)

Adds price types, role-targeting, validity windows and admin notes to `Spree::Price`,
so a variant can carry several competing prices — a wholesale tier, a scheduled sale,
an employee price — and have the right one selected automatically.

This gem is for prices that *are* a different amount. See
[Relationship to solidus_promotions](#relationship-to-solidus_promotions) below if what
you actually want is a discount.

## Requirements

- Solidus **4.5** or newer (`< 5`)
- Rails 7.0–7.2
- Ruby 3.1 or newer

Tested on PostgreSQL, MySQL and SQLite.

### Backporting to Solidus 4.0–4.4

The 4.5 floor exists for one reason: the solidus_admin price types screen inherits from
`SolidusAdmin::ResourcesController`, which was added in Solidus 4.5. Everything else —
the model layer, price selection, the legacy backend, and the API — works from Solidus
4.0.

The seams for a backport are deliberately still in place:

- `config/routes.rb` and `lib/solidus_advanced_pricing/engine.rb` each guard the
  solidus_admin route and menu entry on `Spree.solidus_gem_version >= "4.5"`, so both
  disable themselves on older versions rather than raising.
- The `Gemfile` only installs `solidus_admin` when `SOLIDUS_BRANCH` is `main` or `v4.5+`.
- `spec/features/admin/solidus_admin_price_types_spec.rb` and
  `spec/lib/solidus_advanced_pricing/engine_spec.rb` skip when
  `SolidusAdmin::ResourcesController` is undefined.

So a backport is: lower the floor in the gemspec, add the older versions back to the CI
matrix in `.github/workflows/test.yml`, and the solidus_admin half stays dormant below
4.5 on its own. It was green on 4.1–4.4 that way before the floor was raised.

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
- Copies this gem's three migrations into your app.
- Offers to run `bin/rails db:migrate` for you.

Those migrations add the columns described below to `spree_prices` and seed six
price types (`wholesale`, `sale`, `clearance`, `employee`, `map`, `promotional`). Nothing about existing
pricing behavior changes until you start setting the new columns — see
[Backward compatibility](#backward-compatibility).

`map` (minimum advertised price) and MSRP are easy to confuse but behave oppositely
under cheapest-wins. MAP is a price you are *required* to sell at, so it is a real
selling price and will be selected — a MAP-restricted variant often has no untyped
base price at all. MSRP (not seeded here; add your own type if you want one) is a
suggested price items are typically never sold at; because it sits *above* the
selling price, cheapest-wins never selects it, which makes it a natural compare-at
value for `price_of_type`.

## What it adds to `Spree::Price`

| Column | Type | Meaning |
|---|---|---|
| `price_type_id` | bigint, nullable | Belongs to `SolidusAdvancedPricing::PriceType`. `nil` means the untyped base price — exactly as `role_id: nil` means "inherit from the type" (see below). |
| `role_id` | integer, nullable | Belongs to `Spree::Role`. `nil` does **not** mean "public" — it means the price's visibility is inherited from its price type, if any. See [Effective role](#effective-role) below. |
| `valid_from` | datetime, nullable | Window opens here. `nil` means always open. |
| `valid_to` | datetime, nullable | Window closes here, **exclusive** — a price is valid up to but not including this instant, so a window ending at midnight and the next one starting at midnight don't both match. `nil` means never closes. |
| `admin_notes` | text, nullable | Internal only. Never shown to customers; see [API](#api) for exactly who can see it. |

`price_type_id`, `role_id`, `valid_from` and `valid_to` are all optional. `valid_to`
must be after `valid_from` when both are set.

`SolidusAdvancedPricing::PriceType` also carries a nullable `role_id` of its own —
the type's *default* role. See [Effective role](#effective-role).

## Effective role

A price's visibility to a customer is never decided by its own `role_id` alone. It is
decided by its **effective role**:

```ruby
price.role_id || price.price_type&.role_id
```

**`nil` on a price's own `role_id` means "inherit from the type," not "explicitly
public."** If the price has no type, or its type has no default role, the effective
role is `nil` and the price is visible to everyone, including guests — exactly as
before this feature existed. But once a price type carries a default role, every
price of that type inherits it unless the price sets its own `role_id`.

The deliberate consequence: **if the `employee` type has a default role, you cannot
make an employee-typed price public.** Its `role_id` is either blank (inherits the
type's role) or set to some other role (its own, more specific, targeting) — there is
no value that means "ignore the type's default and show this to everyone." That
tradeoff is the point. It turns this gem's biggest footgun — a price typed `employee`
with no role, visible to every customer including guests — into something a store
fixes once, on the type, instead of something every price author must remember.

Stores are **not** seeded with any type-level defaults; all six seeded types
(`wholesale`, `sale`, `clearance`, `employee`, `map`, `promotional`) ship with
`role_id: nil`, because the correct role for, say, `employee` doesn't exist in every
store. Set it yourself once eligibility should be automatic:

```ruby
employee_role = Spree::Role.find_or_create_by!(name: "employee")
employee_type = SolidusAdvancedPricing::PriceType.find_by(code: "employee")
employee_type.update!(role: employee_role)

# Every price typed `employee`, existing or future, is now visible only to
# customers holding the `employee` role -- no per-price role_id required.
variant.prices.create!(amount: 45, currency: "USD", price_type: employee_type)
```

## A price type is not access control by default

**Setting a price's `price_type` to `employee` does nothing on its own unless the
type itself carries a default role.** Type and role are independent columns until a
store links them via the type's `role_id`. A price typed `employee`, with the type
having no default role and the price's own `role_id` left blank, is visible to every
customer, guests included — the type name alone is just a label for the admin UI and
reporting; it grants no eligibility by itself. Two of the six seeded types,
`wholesale` and `employee`, exist specifically to invite this mistake — and setting a
default role on the type (above) is the recommended way to close it for good, rather
than remembering to set `role_id` on every price of that type.

If you'd rather target one specific price without touching the type, set `role`
directly on it:

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
the ordinary price; only a customer holding that role sees $45. This still works
exactly as before even once the type has its own default role — an explicit
`role_id` on the price always wins over the type's.

## How a price is chosen

For a given variant, currency, and requesting customer, `PriceSelector` picks a price
in three steps:

1. **Filter.** A price survives only if: its currency matches exactly; the current
   time falls inside its validity window (or it has none); and it's visible to the
   customer — its [effective role](#effective-role) is blank, or the customer holds
   that role. If a price type is pinned (see
   [Admin vs. customer lookups](#admin-vs-customer-lookups) below), non-matching
   types are dropped here too.
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

`price_type_id` has three meaningful states in a pricing lookup:

| `price_type_id` | Meaning |
|---|---|
| `nil` | Untyped base prices only. |
| an integer id | Only that type. |
| `:any` | No type filter — every type competes. |

`SolidusAdvancedPricing::PricingOptions.default_price_attributes` pins
`price_type_id` to `nil` and `role_id` to `nil`. This is what
`Spree::Variant#default_price_or_build` and the admin price form build against, so an
admin always edits the untyped base price rather than accidentally landing on a
cheaper sale or wholesale row.

Customer-facing lookups (`PricingOptions.from_line_item`, `.from_context`) set
`price_type_id` to `:any` instead — every type competes — and populate
`customer_role_ids` from the current user's roles, so the full set of eligible prices
is considered. `:any` is a selector-only sentinel; it never reaches `Spree::Price`
as a column value (`PricingOptions#search_arguments` strips it before querying).

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

A second consequence: when a variant has no untyped base price at all (a MAP-only
variant, for example), `variant.price` / `default_price` (and therefore
`display_price`, `display_amount` and `has_default_price?`) fall back to the
cheapest eligible typed price instead of returning nothing, so the admin never
shows a blank price field. The fallback only relaxes the type filter — currency,
the validity window and role visibility still apply, so a variant whose only typed
price is expired or role-targeted still comes back unpriced. `base_price`
deliberately does **not** fall back: it is the compare-at value shown next to the
current price, and if it silently became equal to the current price there would
be nothing left to strike through.

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
- Price types get full CRUD at `/admin/price_types` (`spree.admin_price_types_path`),
  linked from the settings sidebar (Deface override on
  `spree/admin/shared/_configuration_menu`).

**solidus_admin** gets a **price types index only**
(`SolidusAdmin::PriceTypes::Index::Component`, at `solidus_admin.price_types_path`),
linked from the main navigation (registered via `SolidusAdmin::Config.menu_items`
in `lib/solidus_advanced_pricing/engine.rb`) whenever `solidus_admin` is mounted.
It inherits from `SolidusAdmin::ResourcesController`, which is why the gem requires
Solidus 4.5 (see Requirements).
Its rows link back to the legacy backend for edit/new; per-variant price management
stays entirely in the legacy backend. This is deliberate: upstream Solidus's new
admin has no prices screen of its own yet, and building one here would mean guessing
at a design that hasn't landed upstream. Be aware that this component is built
against pre-1.0 `solidus_admin` internals (`SolidusAdmin::UI::Pages::Index::Component`,
`SolidusAdmin::ResourcesController`) and may need updating when you upgrade
`solidus_admin`.

## API

```
GET    /api/variants/:variant_id/prices
GET    /api/variants/:variant_id/prices/:id
POST   /api/variants/:variant_id/prices
PATCH  /api/variants/:variant_id/prices/:id
DELETE /api/variants/:variant_id/prices/:id

GET    /api/price_types
```

Each price is serialized with its advanced attributes — `price_type_code`,
`price_type_name`, `role_id`, `valid_from`, `valid_to` — and `admin_notes` is included
only for a caller who can update that price.

**These endpoints are admin-facing.** Core's `DefaultCustomer` permission set (what every
non-admin API token gets) grants no rights on `Spree::Price` at all, so a non-admin
token receives `401 Unauthorized` on the whole endpoint, not a filtered response.
Headless storefronts do not need this endpoint for normal pricing: core's variants
endpoint already serializes `price` and `display_price` through this gem's selector
automatically, because the selector is registered globally via
`Spree::Config.variant_price_selector_class`.

### Writing prices

```shell
curl -X POST https://store.example/api/variants/42/prices \
  -H "Authorization: Bearer $SPREE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"price": {"amount": "35.00", "price_type_code": "sale",
                 "valid_from": "2026-11-27T00:00:00Z",
                 "valid_to": "2026-12-02T00:00:00Z"}}'
```

- **`price_type_code` is accepted anywhere `price_type_id` is**, and is the better choice
  for anything scripted: ids differ between your staging and production databases, codes
  do not. Sending both is a `422`. Sending `price_type_code: null` (or `""`) means the
  untyped base price, the same as omitting `price_type_id`.
- **`currency` defaults to `Spree::Config.default_pricing_options.currency`** when the
  payload omits it.
- **`price_type` cannot be changed once a price exists.** The admin form has disabled that
  select on persisted prices since 0.2.0, and the model now enforces it, so the API can't
  route around it. Retyping a row reinterprets history instead of correcting it; to fix a
  mistyped price, delete it and create the right one. Re-sending the *same*
  `price_type_id` on an update is fine, so ordinary read-modify-write clients are
  unaffected.
- **`DELETE` soft-deletes** (sets `deleted_at`), so the row stays available to anything
  reporting on what a variant used to cost. Deleted prices are excluded from the listing;
  pass `?show_deleted=true` to include them. Writes never reach a deleted price — updating
  one is a `404`.

Remember that the selector takes the **cheapest** eligible price
([how a price is chosen](#how-a-price-is-chosen)). A role-targeted price written *above*
the untargeted price will never apply, and the API will not warn you about it.

Nothing here stops you deleting a variant's only open-ended price, which leaves that
variant unpriced outside its remaining windows (see
[Backward compatibility](#backward-compatibility)). If that matters to your store, assert
it on your side.

### Batch writes

```
POST /api/prices/batch
```

One call, many prices, across many variants. Always answers `200` with a per-row report,
never a partial `4xx` — a caller that sent 500 rows and got a bare `422` has no way to
know which of them landed.

```shell
curl -X POST https://store.example/api/prices/batch \
  -H "Authorization: Bearer $SPREE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
        "mode": "upsert",
        "dry_run": true,
        "prices": [
          {"sku": "ABC-123", "amount": "35.00", "price_type_code": "sale"},
          {"sku": "DEF-456", "amount": "45.00", "price_type_code": "sale"},
          {"id": 907, "amount": "29.99"}
        ]
      }'
```

```json
{
  "mode": "upsert",
  "dry_run": true,
  "summary": {"created": 1, "updated": 1},
  "results": [
    {"index": 0, "status": "created", "variant_id": 42},
    {"index": 1, "status": "updated", "price_id": 907, "variant_id": 43}
  ]
}
```

Each row takes the same attributes as a single price, plus `id` and `sku`. Per-row
`status` is `created`, `updated`, `unchanged`, `deleted` or `error`; an `error` row carries
`errors` and nothing was written for it.

**Send it as JSON.** Form encoding cannot represent an array of hashes whose rows have
different keys — Rack starts a new hash only when it meets a key it has already seen, so
`[{"id": 1, "amount": 2}, {"variant_id": 3, "amount": 4}]` arrives as
`[{"id": 1, "amount": 2, "variant_id": 3}, {"amount": 4}]`. Set
`Content-Type: application/json`.

#### Naming a row: `id`, or the natural key

**If a row carries `id`, that is the price it changes** — nothing is inferred, nothing can
be mismatched, and `variant_id`/`sku` become optional (the price already knows its
variant; supply one and it is checked, not applied). An `id` that does not exist, or that
has been deleted, is an `error` on that row rather than a new price. This is the right
shape for read-modify-write: fetch the prices, change what you need, send them back.

**Without an `id`, the row is matched on the natural key** — variant, currency, country,
price type, role and `valid_from`. Those are the dimensions a price legitimately varies
on, so an upsert on them is unambiguous, and re-sending the same payload is a no-op rather
than a pile of duplicates.

That second path is not redundant with the first. A payload authored where Solidus ids are
unknown — a supplier feed, a merchandiser's spreadsheet, a backfill from another system —
has no ids to send, and `id`-or-create alone would make every re-run duplicate the whole
file. The natural key is what makes a nightly feed idempotent.

`valid_to` is deliberately *not* in the key: extending or shortening a window edits the
price you already have. `valid_from` is matched to the second, because a client that read a
price back and re-sent its `valid_from` may have dropped the sub-second part in
serialization, and treating that as a different price would duplicate the row — and under
`replace`, discard the original. Sending the `id` sidesteps that question entirely.

Two rows in one payload naming the same price — by `id` or by key — are an `error` on the
second, not a silent last-one-wins.

Fields in the natural key (`currency`, `country_iso`, `role_id`, `valid_from`) can only be
*changed* by a row that names the price by `id`; on a keyed row they are how the price was
found. `price_type` cannot be changed either way — see
[Writing prices](#writing-prices).

#### Modes

- **`upsert`** (default) creates or updates the rows you send and touches nothing else.
- **`replace`** additionally discards prices the payload *left out* — but only of a price
  type the payload named, on a variant the payload named. A `replace` that sends one sale
  price will not reach that variant's base price or its wholesale tier, and will not reach
  any other variant. Deleted rows appear in the report with `status: "deleted"`.

#### `dry_run`

`dry_run: true` does the real work against the database inside a transaction and rolls it
back, so the report reflects what the write would actually do — validations, type casting
and constraints included — rather than a guess at it. Ids are omitted from `created` rows
on a dry run, since they are about to stop existing.

**Use it.** The failure mode of a bulk price load is a silent one.

#### Atomicity

Rows are applied independently, each in its own savepoint: one bad row does not take the
batch down, and the successful rows are committed. This is what makes a row-wise retry
possible. If you need all-or-nothing, run the payload with `dry_run: true` first and only
send it for real once the report is clean.

#### Limits and store policy

`Spree::Config` is not involved; the extension has its own configuration:

```ruby
SolidusAdvancedPricing.configure do |config|
  config.batch_row_limit = 500 # default

  # Called once every row is written and before the transaction commits.
  # Raise to abort the whole batch.
  config.batch_guard = ->(batch) do
    raise TooMuchMovement if batch.summary.fetch(:updated, 0) > 200
  end
end
```

A batch over `batch_row_limit` is refused with a `422` before any row is looked at — a
synchronous request has to stay inside the web timeout, and anything larger belongs in a
background job.

`batch_guard` is the seam for store policy — "refuse a batch that moves more than N% of
prices by more than X%" — which does not belong in a general-purpose extension but does
need somewhere to stand where it can see the finished picture and still stop it.

### Reading price types

`GET /api/price_types` lists the types a price payload may reference — `id`, `code`,
`name`, `position` and the type's default `role_id` — in `position` order. Retired
(discarded) types are omitted, since they are no longer a valid choice; historical prices
still report their own type's code through the prices endpoints. The endpoint is
read-only and admin-authorized: creating a pricing dimension is an admin act, not an API
one.

## Storefront: compare-at (strikethrough) pricing

`Spree::Variant#price_of_type` and `#base_price` fetch a specific typed price
alongside the customer's normal price, so a storefront can render a struck-through
"was" price next to an active sale:

```erb
<% base    = variant.base_price(current_pricing_options) %>
<% current = variant.price_for_options(current_pricing_options) %>

<% if base && current && base.amount > current.amount %>
  <s><%= base.display_amount %></s>
<% end %>
<%= current.display_amount %>
```

`price_of_type` takes the same pricing options as `price_for_options`, so the
comparison price respects the customer's currency, country, roles, and the current
time — not an admin-context lookup. `nil` means the base (untyped) price, which is
what `base_price` passes under the hood. `price_of_type` also accepts a `PriceType`
record, an id, or a type code (e.g. `variant.price_of_type("sale", current_pricing_options)`);
an unresolvable code raises `ArgumentError` rather than silently falling back to the
base price.

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
