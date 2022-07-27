# frozen_string_literal: true

module Coupons
  class CreateService < BaseService
    def create(**args)
      coupon = Coupon.create!(
        organization_id: args[:organization_id],
        name: args[:name],
        code: args[:code],
        amount_cents: args[:amount_cents],
        amount_currency: args[:amount_currency],
        expiration: args[:expiration]&.to_sym,
        expiration_duration: args[:expiration_duration],
      )

      result.coupon = coupon
      track_coupon_created(result.coupon)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    def track_coupon_created(coupon)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'coupon_created',
        properties: {
          coupon_code: coupon.code,
          coupon_name: coupon.name,
          organization_id: coupon.organization_id
        }
      )
    end
  end
end
