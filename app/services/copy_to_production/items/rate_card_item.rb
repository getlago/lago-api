# frozen_string_literal: true

module CopyToProduction
  module Items
    # Copied along with its product, or with a plan that prices it: its taxes and pricing unit are reused by code or
    # copied before it.
    class RateCardItem < BaseItem
      ATTRIBUTES = %i[
        name code description currency billing_timing applied_pricing_unit_code proration display_on_invoice
        regroup_paid_fees
      ].freeze
      RATE_ATTRIBUTES = %i[
        code effective_from rate_model rate_properties min_amount_cents billing_interval_count billing_interval_unit
        applied_pricing_unit_conversion_rate
      ].freeze
      # Reused only from the live product with the code of its own: the create service refuses a live card with its
      # code in another product.
      def find_existing(source)
        production.rate_cards.joins(:product)
          .find_by(code: source.code, products: {code: source.product.code, deleted_at: nil})
      end

      def dependencies(source)
        dependencies = source.taxes.sort_by(&:code).map { ["tax", it] }
        if source.applied_pricing_unit_code.present?
          pricing_unit = sandbox.pricing_units.find_by(code: source.applied_pricing_unit_code)
          dependencies << ["pricing_unit", pricing_unit] if pricing_unit
        end
        dependencies
      end

      def copy!(source, resolved)
        product = resolved.fetch(["product", source.product_id])

        RateCards::CreateService.call!(
          product:,
          params: source.slice(*ATTRIBUTES).merge(
            product_filter_id: source.product_filter && live_filter(product, source.product_filter).id,
            tax_codes: source.taxes.map(&:code),
            rates: rates_params(source)
          )
        ).rate_card
      end

      private

      # A copied product has every kept filter of the sandbox one; a live product reused by code may lack it.
      def live_filter(product, filter)
        product.filters.find_by(code: filter.code) || not_found!("product_filter")
      end

      # Production starts at the sandbox's active rate, effective from now, followed by its pending rates. The
      # superseded rates are history of the sandbox: a rate cannot be created in the past.
      def rates_params(source)
        now = Time.current
        rates = source.rates.sort_by(&:effective_from)
        active = rates.select { it.effective_from <= now }.last
        pending = rates.select { it.effective_from > now }

        [*([rate_params(active).merge(effective_from: now)] if active), *pending.map { rate_params(it) }]
      end

      # Storage adds each tier's lower bound, which the create service refuses: it takes tiers as the API shows them.
      def rate_params(rate)
        rate.slice(*RATE_ATTRIBUTES).merge(rate_properties: RateProperties.present(rate.rate_properties))
      end
    end
  end
end
