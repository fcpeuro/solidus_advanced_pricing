# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-09-23

### Fixed

- **Installing the gem without registering its price selector broke every
  `variant.price = ...`**, product creation included, with
  `NoMethodError: undefined method 'price_type_id' for an instance of
  Spree::Variant::PricingOptions`. Core calls `default_price` on the way into
  `price=`, and this gem's override reached for a typed fallback through
  `pricing_options.with(price_type_id: :any)` — which only works on this gem's
  own `PricingOptions`. A store that left
  `Spree::Config.variant_price_selector_class` alone got core's, where `with`
  falls through to ActiveSupport's `Object#with` and `public_send`s the key.
  Present since 0.2.0, when the fallback was added.

  The fallback is now skipped unless this gem's pricing options are in play.
  Without the selector there are no typed prices to fall back to, so the right
  answer is core's: nothing.
- `Spree::Variant#price_of_type` and `#base_price` now raise
  `SolidusAdvancedPricing::SelectorNotRegistered`, naming the setting to change,
  instead of a `NoMethodError` about `price_type_id`.

## [0.3.0] - 2026-09-23

### Added

- **Write endpoints for prices.** `POST`, `PATCH` and `DELETE` on
  `/api/variants/:variant_id/prices`, so prices can be administered over the API rather
  than only read. `DELETE` soft-deletes.
- **`price_type_code` is accepted anywhere `price_type_id` is** on a price payload. Ids
  are per-database and codes are not, so a payload written against staging works unchanged
  against production. Sending both is a `422`; an explicit null means the untyped base
  price.
- **`GET /api/price_types`**, listing the types a price payload may reference with their
  ids, codes, names, positions and default roles. Read-only and admin-authorized.
- **Batch writes: `POST /api/prices/batch`** and the `SolidusAdvancedPricing::PriceBatch`
  service behind it. Many prices across many variants in one call, matched on the natural
  key (variant, currency, country, price type, role, `valid_from`) so re-sending a payload
  is a no-op rather than a pile of duplicates. Always answers `200` with a per-row report.
  - `dry_run: true` runs the real work in a transaction and rolls it back, so the report
    reflects what the write would do rather than a guess at it.
  - A row carrying `id` names that price outright: `variant_id`/`sku` become optional and
    are checked rather than applied, natural-key fields such as `currency`, `role_id` and
    `valid_from` become editable, and an unknown or deleted `id` is a row error rather than
    a new price.
  - `mode: "replace"` also discards prices the payload left out — scoped to price types and
    variants the payload actually named.
  - Rows are applied independently in savepoints, so one bad row does not take the batch
    down and a row-wise retry is possible.
  - `SolidusAdvancedPricing.config.batch_row_limit` (default 500) and
    `config.batch_guard`, a callable invoked with every row written and nothing committed,
    which may raise to abort. The seam for store policy that does not belong in the gem.
- `currency` now defaults to `Spree::Config.default_pricing_options.currency` when a
  created price omits it.

### Fixed

- **`GET /api/variants/:variant_id/prices` listed soft-deleted prices.**
  `Spree::Variant#prices` is declared `-> { with_discarded }` in core, which the endpoint
  inherited, so anything an admin had deleted still came back. Deleted prices are now
  excluded by default; `?show_deleted=true` opts back in.

### Changed

- **`price_type` is now immutable on a persisted price**, raising a validation error
  instead of silently retyping the row. The admin form has disabled that select since
  0.2.0; this closes the same gap at the model layer so the API cannot route around it.
  Re-sending an unchanged `price_type_id` is still fine. Code that deliberately retypes an
  existing price must now discard it and create a replacement, or use `update_columns` to
  bypass validation in a data migration.

## [0.2.0] - 2026-09-23

### Added

- Price types can carry a **default role**. A price with no role of its own inherits its
  type's role, so a type like `employee` can be targeted once instead of on every price.
  A price's own role still wins when set. This is the recommended way to avoid publishing
  a role-named price to everyone.
- `map` and `promotional` price types are now seeded, bringing the set to six.

### Fixed

- **An untyped price could not be created in the admin.** The price type select had no
  blank option, and defaulted to its first entry — so every price created through the UI
  was silently typed `wholesale`. A regression from making `price_type_id` nullable in
  0.1.0.
- **Validity windows lost their time.** `valid_from` and `valid_to` are datetime columns,
  but the form used Solidus' `.datepicker` class, which is initialised as flatpickr
  without `enableTime` and can only produce a date. Any time an admin set was dropped to
  midnight. Now rendered as native `datetime-local` inputs.
- Deleting a `Spree::Role` referenced by a price type's default role raised a raw foreign
  key violation instead of being blocked with an error.

### Changed

- **The price type is now locked once a price exists**, matching how core treats the
  country field. Changing which pricing dimension an existing row belongs to reinterprets
  historical data rather than correcting it.

## [0.1.0] - 2026-09-23

Initial release.

### Added

- **Price types** — an admin-managed model with a code, name and position. `price_type_id`
  on `spree_prices` is nullable; `NULL` means the untyped base price.
- **Validity windows** — optional `valid_from` / `valid_to` on each price. `valid_to` is
  exclusive.
- **Role targeting** — an optional `Spree::Role` per price. Blank means every customer,
  guests included. Role is *eligibility only*, never specificity: a role-targeted price set
  above the untargeted price never applies.
- **`admin_notes`** — internal commentary on a price, never rendered to customers.
- A `PriceSelector` and `PricingOptions` registered through
  `Spree::Config.variant_price_selector_class`: filter by currency, type, window and role;
  prefer the country-specific bucket over the any-country fallback; cheapest wins.
- `Spree::Variant#price_of_type` and `#base_price` for compare-at (strikethrough) display.
- `Spree::Variant.with_prices` now honours validity windows and role targeting, so a
  variant whose only price has expired no longer counts as purchasable.
- Full legacy backend admin: price fields, table columns, a price types CRUD, and a
  settings sidebar link. A price types index for `solidus_admin`.
- `GET /api/variants/:variant_id/prices` — admin-facing; `admin_notes` is exposed only to
  a user who can update the price.

### Security

- Pricing cache keys include the customer's pricing-relevant roles and a coarse time
  bucket. Without the role component a role-targeted price would be cached and served to
  guests.

[0.3.1]: https://github.com/fcpeuro/solidus_advanced_pricing/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/fcpeuro/solidus_advanced_pricing/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/fcpeuro/solidus_advanced_pricing/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fcpeuro/solidus_advanced_pricing/releases/tag/v0.1.0
