# frozen_string_literal: true

module Coupons
  class CreateService < BaseService
    def create(**args)
      coupon = Coupon.create!(
        organization_id: args[:organization_id],
        name: args[:name],
        code: args[:code],
        coupon_type: args[:coupon_type]&.to_sym,
        amount_cents: args[:amount_cents],
        amount_currency: args[:amount_currency],
        day_count: args[:day_count],
        expiration: args[:expiration]&.to_sym,
        expiration_duration: args[:expiration_duration],
        expiration_users: args[:expiration_users],
      )

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
