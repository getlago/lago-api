# frozen_string_literal: true

# Enforces a slug-safe `code` on v2 catalog objects (Product, ProductCategory,
# ProductFilter, RateCard, RateCardRate, CatalogPlan, RatePhase). Codes are
# member-route params, so restricting them to a URL-safe charset keeps every
# code addressable and avoids collisions with nested route segments. The
# leading negative lookahead rejects an all-dot code (`.`, `..`, …): those are
# path-segment specials that clients and proxies normalize away, so they are
# not reliably addressable. allow_blank leaves the empty case to the presence
# validation.
module CatalogCodeFormat
  extend ActiveSupport::Concern

  CODE_FORMAT = /\A(?!\.+\z)[a-zA-Z0-9_\-.]+\z/

  included do
    validates :code, format: {with: CODE_FORMAT}, allow_blank: true
  end
end
