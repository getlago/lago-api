# frozen_string_literal: true

module V2
  class RateCardSerializer < ModelSerializer
    def serialize
      payload = {
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
        rates_count: model.rates.size,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        **deleted_at_payload
      }

      payload[:active_rate] = active_rate if include?(:active_rate)
      payload.merge!(taxes) if include?(:taxes)
      # Full timeline for activity-log payloads; API payloads stay lean.
      payload.merge!(rates) if include?(:rates)
      payload
    end

    private

    def active_rate
      rate = model.active_rate
      return if rate.nil?

      ::V2::RateCardRateSerializer.new(rate, includes: nested_includes).serialize
    end

    # Latest effective_from first, as /rates lists them. Sorted in memory, so that every
    # status reads its siblings from the loaded association rather than querying them.
    def rates
      ::CollectionSerializer.new(
        model.rates.sort_by(&:effective_from).reverse,
        ::V2::RateCardRateSerializer,
        collection_name: "rates",
        includes: nested_includes
      ).serialize
    end

    # A tax discarded between the query of the links and the preload of their taxes loads as nil.
    def taxes
      ::CollectionSerializer.new(
        model.applied_taxes.listed.filter_map(&:tax),
        ::V1::TaxSerializer,
        collection_name: "taxes"
      ).serialize
    end
  end
end
