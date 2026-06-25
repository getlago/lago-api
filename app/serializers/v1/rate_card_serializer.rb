# frozen_string_literal: true

module V1
  class RateCardSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_product_item_id: model.product_item_id,
        lago_product_item_filter_id: model.product_item_filter_id,
        name: model.name,
        code: model.code,
        description: model.description,
        currency: model.currency,
        billing_timing: model.billing_timing,
        proration: model.proration,
        display_on_invoice: model.display_on_invoice,
        regroup_paid_fees: model.regroup_paid_fees,
        applied_pricing_unit_code: model.applied_pricing_unit_code,
        wallet_targetable: model.wallet_targetable,
        rates_count: model.rates.count,
        created_at: model.created_at.iso8601
      }

      payload[:active_rate] = active_rate if include?(:active_rate)
      payload
    end

    private

    def active_rate
      rate = model.active_rate
      return if rate.nil?

      ::V1::RateCardRateSerializer.new(rate).serialize
    end
  end
end
