# frozen_string_literal: true

module AppliedCoupons
  class CreateService < BaseService
    def create(**args)
      @customer = Customer.find_by(
        id: args[:customer_id],
        organization_id: args[:organization_id],
      )

      @coupon = Coupon.active.find_by(
        id: args[:coupon_id],
        organization_id: args[:organization_id],
      )

      process_creation(
        amount_cents: args[:amount_cents] || coupon&.amount_cents,
        amount_currency: args[:amount_currency] || coupon&.amount_currency,
      )
    end

    def create_from_api(organization:, args:)
      @customer = Customer.find_by(
        external_id: args[:external_customer_id],
        organization_id: organization.id,
      )

      @coupon = Coupon.active.find_by(
        code: args[:coupon_code],
        organization_id: organization.id,
      )

      process_creation(
        amount_cents: args[:amount_cents] || coupon&.amount_cents,
        amount_currency: args[:amount_currency] || coupon&.amount_currency,
      )
    end

    private

    attr_reader :customer, :coupon

    def check_preconditions
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'coupon') unless coupon
      return unless coupon_already_applied?

      result.single_validation_failure!(
        field: 'coupon',
        error_code: 'coupon_already_applied',
      )
    end

    def process_creation(amount_cents:, amount_currency:)
      check_preconditions
      return result if result.error

      applied_coupon = AppliedCoupon.new(
        customer: customer,
        coupon: coupon,
        amount_cents: amount_cents,
        amount_currency: amount_currency,
      )

      ActiveRecord::Base.transaction do
        currency_result = Customers::UpdateService.new(nil).update_currency(
          customer: customer,
          currency: amount_currency,
        )
        return currency_result unless currency_result.success?

        applied_coupon.save!
      end

      result.applied_coupon = applied_coupon
      track_applied_coupon_created(result.applied_coupon)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def coupon_already_applied?
      customer.applied_coupons.active.exists?
    end

    def track_applied_coupon_created(applied_coupon)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'applied_coupon_created',
        properties: {
          customer_id: applied_coupon.customer.id,
          coupon_code: applied_coupon.coupon.code,
          coupon_name: applied_coupon.coupon.name,
          organization_id: applied_coupon.coupon.organization_id,
        },
      )
    end
  end
end
