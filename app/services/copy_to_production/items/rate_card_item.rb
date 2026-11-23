# frozen_string_literal: true

module CopyToProduction
  module Items
    # Copied along with its product only: its taxes and pricing unit are reused by code or copied before it.
    class RateCardItem < BaseItem
      ATTRIBUTES = %i[
        name code description currency billing_timing applied_pricing_unit_code proration display_on_invoice
        regroup_paid_fees
      ].freeze
      RATE_ATTRIBUTES = %i[
        code effective_from rate_model rate_properties min_amount_cents billing_interval_count billing_interval_unit
        applied_pricing_unit_conversion_rate
      ].freeze
      PRELOADS = [:product_filter, :rates, :taxes].freeze

      def find_source(id)
        sandbox.rate_cards.includes(*PRELOADS).find_by(id:)
      end

      # A rate card is only copied as part of a new product, so it is never reused: a live card with its code belongs
      # to another product, which refuses the copy.
      def find_existing(_source)
        nil
      end

      # A prorated card needs a recurring metric that is not a weighted sum, which a reused live metric may not be.
      def refusal(source)
        return "copy_to_production_code_conflict" if production.rate_cards.exists?(code: source.code)

        "copy_to_production_metric_mismatch" if source.proration? && prorating_metric_mismatch?(source.product)
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
            # Deleting a product filter discards its rate cards, so a kept card's filter is kept and was copied.
            product_filter_id: source.product_filter && product.filters.find_by!(code: source.product_filter.code).id,
            tax_codes: source.taxes.map(&:code),
            rates: rates_params(source)
          )
        ).rate_card
      end

      def unique_indexes
        {"index_rate_cards_on_organization_id_and_code" => :code}
      end

      private

      # As RateCard#validate_proration reads it on the live metric the card will bill: the live product's, or the
      # production metric with the code of the product's.
      def prorating_metric_mismatch?(product)
        return false unless product.metered?

        live_product = production.products.includes(:billable_metric).find_by(code: product.code)
        live_metric = if live_product
          live_product.billable_metric
        elsif product.billable_metric
          production.billable_metrics.find_by(code: product.billable_metric.code)
        end
        return false unless live_metric

        !live_metric.recurring? || live_metric.weighted_sum_agg?
      end

      # Production starts at the sandbox's active rate, effective from now, followed by its pending rates. The
      # superseded rates are history of the sandbox: a rate cannot be created in the past.
      def rates_params(source)
        now = Time.current
        rates = source.rates.sort_by(&:effective_from)
        active = rates.select { it.effective_from <= now }.last
        pending = rates.select { it.effective_from > now }

        [*([active.slice(*RATE_ATTRIBUTES).merge(effective_from: now)] if active), *pending.map { it.slice(*RATE_ATTRIBUTES) }]
      end
    end
  end
end
