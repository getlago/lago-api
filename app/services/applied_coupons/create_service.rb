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
        percentage_rate: args[:percentage_rate] || coupon&.percentage_rate,
        frequency: args[:frequency] || coupon&.frequency,
        frequency_duration: args[:frequency_duration] || coupon&.frequency_duration,
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
        percentage_rate: args[:percentage_rate] || coupon&.percentage_rate,
        frequency: args[:frequency] || coupon&.frequency,
        frequency_duration: args[:frequency_duration] || coupon&.frequency_duration,
      )
    end

    private

    attr_reader :customer, :coupon

    def check_preconditions
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'coupon') unless coupon
      return result.not_allowed_failure!(code: 'plan_overlapping') if plan_limitation_overlapping?
      return if reusable_coupon?

      result.single_validation_failure!(field: 'coupon', error_code: 'coupon_is_not_reusable')
    end

    def process_creation(applied_coupon_attributes)
      check_preconditions
      return result if result.error

      applied_coupon = AppliedCoupon.new(
        customer: customer,
        coupon: coupon,
        amount_cents: applied_coupon_attributes[:amount_cents],
        amount_currency: applied_coupon_attributes[:amount_currency],
        percentage_rate: applied_coupon_attributes[:percentage_rate],
        frequency: applied_coupon_attributes[:frequency],
        frequency_duration: applied_coupon_attributes[:frequency_duration],
        frequency_duration_remaining: applied_coupon_attributes[:frequency_duration],
      )

      if coupon.fixed_amount?
        ActiveRecord::Base.transaction do
          currency_result = Customers::UpdateService.new(nil).update_currency(
            customer: customer,
            currency: applied_coupon_attributes[:amount_currency],
          )
          return currency_result unless currency_result.success?

          applied_coupon.save!
        end
      else
        applied_coupon.save!
      end

      result.applied_coupon = applied_coupon
      track_applied_coupon_created(result.applied_coupon)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def reusable_coupon?
      return true if coupon.reusable?

      customer.applied_coupons.where(coupon_id: coupon.id).none?
    end

    def plan_limitation_overlapping?
      return false unless coupon.limited_plans?

      customer
        .applied_coupons
        .active
        .joins(coupon: :coupon_plans)
        .where(coupon_plans: { plan_id: coupon.coupon_plans.select(:plan_id) })
        .exists?
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
