# frozen_string_literal: true

module Coupons
  class UpdateService < BaseService
    def update(**args)
      coupon = result.user.coupons.find_by(id: args[:id])
      return result.fail!('not_found') unless coupon

      coupon.name = args[:name]
      coupon.code = args[:code]
      coupon.amount_cents = args[:amount_cents]
      coupon.amount_currency = args[:amount_currency]
      coupon.expiration = args[:expiration]&.to_sym
      coupon.expiration_duration = args[:expiration_duration]

      coupon.save!

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
