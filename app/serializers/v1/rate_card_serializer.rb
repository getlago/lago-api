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
        created_at: model.created_at.iso8601
      }

      payload.merge!(rates) if include?(:rates)
      payload
    end

    private

    def rates
      ::CollectionSerializer.new(
        model.rates,
        ::V1::RateCardRateSerializer,
        collection_name: "rates"
      ).serialize
    end
  end
end
