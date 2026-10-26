# frozen_string_literal: true

module V2
  class RateCardUsageSerializer < ModelSerializer
    def serialize
      {
        rate_card_code: rate_card.code,
        rate_card_name: rate_card.name,
        product_code: product.code,
        product_name: product.name,
        product_category_code: product.product_category&.code,
        product_category_name: product.product_category&.name,
        product_filter_code: product_filter&.code,
        product_filter_name: product_filter&.name,
        invoice_display_name: (product_filter || product).invoice_name,
        product_type: product.product_type,
        billable_metric_code: product.billable_metric&.code,
        billing_timing: rate_card.billing_timing,
        from_datetime: format_time(model.billing_segment.started_at),
        to_datetime: format_time(model.billing_segment.ended_at),
        rate_phase_code: model.rate_phase&.code,
        rate_phase_name: model.rate_phase&.name,
        rate_source: model.rate_source,
        rate_model: model.billing_segment.rate.rate_model,
        rate_properties: model.billing_segment.rate_properties,
        units: model.units.to_s,
        events_count: model.events_count,
        amount_cents: model.amount_cents
      }
    end

    private

    def rate_card
      model.contract_rate_card.rate_card
    end

    def product
      rate_card.product
    end

    def product_filter
      rate_card.product_filter
    end
  end
end
