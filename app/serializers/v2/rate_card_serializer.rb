# frozen_string_literal: true

module V2
  class RateCardSerializer < ModelSerializer
    EXPANDABLE_RELATIONS = {
      active_rate: nil,
      # Few per card, attached one by one through tax_codes.
      taxes: nil,
      # One per price change, /rates returns them whole.
      rates: :rates,
      product: {product: %i[product_category billable_metric]},
      product_filter: {product_filter: {values: :billable_metric_filter}}
    }.freeze

    def self.expandable_relations
      EXPANDABLE_RELATIONS
    end

    def serialize
      {
        lago_id: model.id,
        product_code: model.product.code,
        product_filter_code: model.product_filter&.code,
        name: model.name,
        code: model.code,
        description: model.description,
        currency: model.currency,
        billing_timing: model.billing_timing,
        proration: model.proration,
        display_on_invoice: model.display_on_invoice,
        regroup_paid_fees: model.regroup_paid_fees,
        applied_pricing_unit_code: model.applied_pricing_unit_code,
        **counts,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        **deleted_at_payload,
        **expanded_payload
      }
    end

    private

    def counts = include?(:counts) ? {rates_count: model.rates.size} : {}

    def expand_active_rate
      model.active_rate&.then { ::V2::RateCardRateSerializer.new(it, includes: nested_includes).serialize }
    end

    # Forwards :counts so that the activity log, the only caller passing it, keeps V1's zeros on its
    # taxes. A tax discarded between the query of the links and the preload of their taxes loads as nil.
    def expand_taxes
      model.applied_taxes.listed.filter_map(&:tax).map do |tax|
        ::V2::TaxSerializer.new(tax, includes: nested_includes(forward: %i[counts])).serialize
      end
    end

    # Latest effective_from first, as /rates lists them. Sorted in memory, so that every
    # status reads its siblings from the loaded association rather than querying them.
    def expand_rates
      model.rates.sort_by(&:effective_from).reverse.map do |rate|
        ::V2::RateCardRateSerializer.new(rate, includes: nested_includes).serialize
      end
    end

    def expand_product
      ::V2::ProductSerializer.new(model.product, includes: nested_includes).serialize
    end

    def expand_product_filter
      model.product_filter&.then { ::V2::ProductFilterSerializer.new(it, includes: nested_includes).serialize }
    end
  end
end
