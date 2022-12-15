# frozen_string_literal: true

module Coupons
  class UpdateService < BaseService
    def update(args)
      coupon = result.user.coupons.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'coupon') unless coupon

      coupon.name = args[:name]
      coupon.expiration = args[:expiration]&.to_sym
      coupon.expiration_at = args[:expiration_at]

      unless coupon.attached_to_customers?
        coupon.code = args[:code]
        coupon.coupon_type = args[:coupon_type]
        coupon.amount_cents = args[:amount_cents]
        coupon.amount_currency = args[:amount_currency]
        coupon.percentage_rate = args[:percentage_rate]
        coupon.frequency = args[:frequency]
        coupon.frequency_duration = args[:frequency_duration]
        coupon.reusable = args[:reusable]
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
      coupon.expiration = params[:expiration] if params.key?(:expiration)
      coupon.expiration_at = params[:expiration_at] if params.key?(:expiration_at)

      unless coupon.attached_to_customers?
        coupon.code = params[:code] if params.key?(:code)
        coupon.coupon_type = params[:coupon_type] if params.key?(:coupon_type)
        coupon.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
        coupon.amount_currency = params[:amount_currency] if params.key?(:amount_currency)
        coupon.percentage_rate = params[:percentage_rate] if params.key?(:percentage_rate)
        coupon.frequency = params[:frequency] if params.key?(:frequency)
        coupon.frequency_duration = params[:frequency_duration] if params.key?(:frequency_duration)
        coupon.reusable = params[:reusable] if params.key?(:reusable)
      end

      coupon.save!

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
