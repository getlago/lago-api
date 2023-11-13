# frozen_string_literal: true

module Credits
  class AppliedCouponService < BaseService
    def initialize(invoice:, applied_coupon:)
      @invoice = invoice
      @applied_coupon = applied_coupon

      super(nil)
    end

    def call
      return result unless matches_currency?
      return result if already_applied?
      return result unless fees.any?

      credit_amount = compute_amount

      new_credit = Credit.create!(
        invoice:,
        applied_coupon:,
        amount_cents: credit_amount,
        amount_currency: invoice.currency,
        before_taxes: true,
      )

      fees.reload.each do |fee|
        fee.precise_coupons_amount_cents += (
          credit_amount * (fee.amount_cents - fee.precise_coupons_amount_cents)
        ).fdiv(base_amount_cents)

        fee.precise_coupons_amount_cents = fee.amount_cents if fee.amount_cents < fee.precise_coupons_amount_cents
        fee.save!
      end

      applied_coupon.frequency_duration_remaining -= 1 if applied_coupon.recurring?
      if should_terminate_applied_coupon?(credit_amount)
        applied_coupon.mark_as_terminated!
      elsif applied_coupon.recurring?
        applied_coupon.save!
      end

      invoice.coupons_amount_cents += new_credit.amount_cents
      invoice.sub_total_excluding_taxes_amount_cents -= new_credit.amount_cents

      result.credit = new_credit
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :applied_coupon

    delegate :coupon, to: :applied_coupon

    def matches_currency?
      return true unless applied_coupon.coupon.fixed_amount?

      applied_coupon.amount_currency == invoice.currency
    end

    def already_applied?
      invoice.credits.where(applied_coupon_id: applied_coupon.id).exists?
    end

    def compute_amount
      if applied_coupon.coupon.percentage?
        discounted_value = base_amount_cents * applied_coupon.percentage_rate.fdiv(100)

        return (discounted_value >= base_amount_cents) ? base_amount_cents : discounted_value.round
      end

      if applied_coupon.recurring? || applied_coupon.forever?
        return base_amount_cents if applied_coupon.amount_cents > base_amount_cents

        applied_coupon.amount_cents
      else
        return base_amount_cents if remaining_amount > base_amount_cents

        remaining_amount
      end
    end

    def remaining_amount
      return @remaining_amount if @remaining_amount

      already_applied_amount = applied_coupon.credits.sum(:amount_cents)
      @remaining_amount = applied_coupon.amount_cents - already_applied_amount
    end

    def should_terminate_applied_coupon?(credit_amount)
      return false if applied_coupon.forever?

      if applied_coupon.once?
        applied_coupon.coupon.percentage? || credit_amount >= remaining_amount
      else
        applied_coupon.frequency_duration_remaining <= 0
      end
    end

    # TODO: ensure targeted amount is right with BM/plan limitation
    def base_amount_cents
      if applied_coupon.coupon.limited_billable_metrics? || applied_coupon.coupon.limited_plans?
        return fees.sum(:amount_cents)
      end

      invoice.sub_total_excluding_taxes_amount_cents
    end

    def fees
      @fees ||= if applied_coupon.coupon.limited_billable_metrics?
        billable_metric_related_fees
      elsif applied_coupon.coupon.limited_plans?
        plan_related_fees
      else
        invoice.fees
      end
    end

    def plan_related_fees
      invoice
        .fees
        .joins(subscription: :plan)
        .where(plan: { id: applied_coupon.coupon.parent_and_overriden_plans.map(&:id) })
    end

    def billable_metric_related_fees
      invoice
        .fees
        .joins(charge: :billable_metric)
        .where(billable_metric: { id: applied_coupon.coupon.coupon_targets.select(:billable_metric_id) })
    end
  end
end
