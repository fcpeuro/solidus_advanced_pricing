# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.0]: https://github.com/fcpeuro/solidus_advanced_pricing/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fcpeuro/solidus_advanced_pricing/releases/tag/v0.1.0
