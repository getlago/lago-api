# frozen_string_literal: true

module AppliedCoupons
  class CreateService < BaseService
    def create(**args)
      @customer = Customer.find_by(
        id: args[:customer_id],
        organization_id: args[:organization_id],
      )
      return result.fail!('not_found') if customer.blank?

      @coupon = Coupon.active.find_by(
        id: args[:coupon_id],
        organization_id: args[:organization_id],
      )
      return result.fail!('not_found') if coupon.blank?

      process_creation(
        amount_cents: args[:amount_cents] || coupon.amount_cents,
        amount_currency: args[:amount_currency] || coupon.amount_currency,
      )
    end

    private

    attr_reader :customer, :coupon

    def process_creation(amount_cents:, amount_currency:)
      return result.fail!('no_active_subscription') unless active_subscription?
      return result.fail!('coupon_already_applied') if coupon_already_applied?
      return result.fail!('currencies_does_not_match') unless applicable_currency?(amount_currency)

      applied_coupon = AppliedCoupon.create!(
        customer: customer,
        coupon: coupon,
        amount_cents: amount_cents,
        amount_currency: amount_currency,
      )

      result.applied_coupon = applied_coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def active_subscription?
      customer.active_subscription.present?
    end

    def coupon_already_applied?
      customer.applied_coupons.active.where(coupon_id: coupon.id).exists?
    end

    def applicable_currency?(currency)
      customer.active_subscription.plan.amount_currency == currency
    end
  end
end
