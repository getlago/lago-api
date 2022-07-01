# frozen_string_literal: true

module V1
  class PlanSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        name: model.name,
        created_at: model.created_at.iso8601,
        code: model.code,
        interval: model.interval,
        description: model.description,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        trial_period: model.trial_period,
        pay_in_advance: model.pay_in_advance,
        bill_charges_monthly: model.bill_charges_monthly,
      }

      payload = payload.merge(charges) if include?(:charges)

      payload
    end

    private

    def charges
      ::CollectionSerializer.new(model.charges, ::V1::ChargeSerializer, collection_name: 'charges').serialize
    end
  end
end
