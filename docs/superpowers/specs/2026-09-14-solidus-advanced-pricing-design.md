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
