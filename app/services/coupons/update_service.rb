# frozen_string_literal: true

module Coupons
  class UpdateService < BaseService
    def update(**args)
      coupon = result.user.coupons.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'coupon') unless coupon

      coupon.name = args[:name]

      unless coupon.attached_to_customers?
        coupon.code = args[:code]
        coupon.amount_cents = args[:amount_cents]
        coupon.amount_currency = args[:amount_currency]
        coupon.expiration = args[:expiration]&.to_sym
        coupon.expiration_duration = args[:expiration_duration]
      end

      coupon.save!

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def update_from_api(organization:, code:, params:)
      coupon = organization.coupons.find_by(code: code)
      return result.not_found_failure!(resource: 'coupon') unless coupon

      coupon.name = params[:name] if params.key?(:name)

      unless coupon.attached_to_customers?
        coupon.code = params[:code] if params.key?(:code)
        coupon.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
        coupon.amount_currency = params[:amount_currency] if params.key?(:amount_currency)
        coupon.expiration = params[:expiration] if params.key?(:expiration)
        coupon.expiration_duration = params[:expiration_duration] if params.key?(:expiration_duration)
      end

      coupon.save!

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
