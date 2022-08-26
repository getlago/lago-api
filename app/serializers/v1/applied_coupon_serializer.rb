# frozen_string_literal: true

module V1
  class AppliedCouponSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_coupon_id: model.coupon.id,
        coupon_code: model.coupon.code,
        lago_customer_id: model.customer.id,
        external_customer_id: model.customer.external_id,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        expiration_date: model.coupon.expiration_date&.iso8601,
        created_at: model.created_at.iso8601,
        terminated_at: model.terminated_at&.iso8601,
      }
    end
  end
end
