# frozen_string_literal: true

module V1
  class CouponSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        coupon_type: model.coupon_type,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        percentage_rate: model.percentage_rate,
        frequency: model.frequency,
        frequency_duration: model.frequency_duration,
        created_at: model.created_at.iso8601,
        expiration: model.expiration,
        expiration_duration: model.expiration_duration
      }
    end
  end
end
