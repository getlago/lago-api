# frozen_string_literal: true

module V1
  class CouponSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        coupon_type: model.coupon_type,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        percentage_rate: model.percentage_rate,
        frequency: model.frequency,
        frequency_duration: model.frequency_duration,
        reusable: model.reusable,
        limited_plans: model.limited_plans,
        created_at: model.created_at.iso8601,
        expiration: model.expiration,
        expiration_at: model.expiration_at&.iso8601,
      }.merge(legacy_values)

      payload = payload.merge(plans) if include?(:plans)

      payload
    end

    private

    def legacy_values
      ::V1::Legacy::CouponSerializer.new(
        model,
      ).serialize
    end

    def plans
      ::CollectionSerializer
        .new(model.plans, ::V1::PlanSerializer, collection_name: 'plans').serialize
    end
  end
end
