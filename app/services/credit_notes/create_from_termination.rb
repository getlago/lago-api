# frozen_string_literal: true

module CreditNotes
  class CreateFromTermination < BaseService
    Result = CreditNotes::CreateService::Result

    def initialize(subscription:, reason: "order_change", upgrade: false, context: nil)
      @subscription = subscription
      @reason = reason
      @upgrade = upgrade
      @context = context

      super
    end

    def call
      return result if (last_subscription_fee&.amount_cents || 0).zero? || last_subscription_fee.invoice.voided?

      base_creditable_amount = calculate_base_creditable_amount
      return result if base_creditable_amount.zero?

      credit_amount_cents, refund_amount_cents = calculate_credit_and_refund_amounts(base_creditable_amount)

      CreditNotes::CreateService.call(
        invoice: last_subscription_fee.invoice,
        credit_amount_cents:,
        refund_amount_cents:,
        items: [
          {
            fee_id: last_subscription_fee.id,
            amount_cents: base_creditable_amount.truncate(CreditNote::DB_PRECISION_SCALE)
          }
        ],
        reason: reason.to_sym,
        automatic: true,
        context:
      )
    end

    private

    attr_accessor :subscription, :reason, :upgrade, :context

    delegate :plan, :terminated_at, :customer, to: :subscription

    def calculate_base_creditable_amount
      amount = calculate_base_unused_amount
      return 0 unless amount.positive?

      # NOTE: In some cases, if the fee was already prorated (in case of multiple upgrade) the amount
      #       could be greater than the last subscription fee amount.
      #       In that case, we have to use the last subscription fee amount
      amount = last_subscription_fee.amount_cents if amount > last_subscription_fee.amount_cents

      # NOTE: if credit notes were already issued on the fee,
      #       we have to deduct them from the prorated amount
      amount -= last_subscription_fee.credit_note_items.sum(:amount_cents)
      return 0 unless amount.positive?

      amount
    end

    def last_subscription_fee
      @last_subscription_fee ||= subscription.fees.subscription.order(created_at: :desc).first
    end

    def calculate_base_unused_amount
      day_price * remaining_duration
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        terminated_at
      )
    end

    def plan_amount_cents
      last_subscription_fee&.amount_details&.[]("plan_amount_cents") || plan.amount_cents
    end

    def to_date
      date_service.next_end_of_period.to_date
    end

    def day_price
      date_service.single_day_price(plan_amount_cents:)
    end

    def terminated_at_in_timezone
      terminated_at.in_time_zone(customer.applicable_timezone)
    end

    def remaining_duration
      billed_from = terminated_at_in_timezone.end_of_day.utc.to_date
      billed_from -= 1.day if upgrade

      if plan.has_trial? && subscription.trial_end_date >= billed_from
        billed_from = if subscription.trial_end_date > to_date
          to_date
        else
          subscription.trial_end_date - 1.day
        end
      end

      duration = (to_date - billed_from).to_i

      duration.negative? ? 0 : duration
    end

    def calculate_credit_and_refund_amounts(base_creditable_amount)
      # Calculate the total creditable amount (including taxes)
      total_creditable_amount = adjust_for_coupon_and_taxes(base_creditable_amount)

      refund_amount_cents = 0

      credit_amount_cents = total_creditable_amount - refund_amount_cents

      [credit_amount_cents, refund_amount_cents]
    end

    def adjust_for_coupon_and_taxes(item_amount)
      precise_amount_cents = item_amount.truncate(CreditNote::DB_PRECISION_SCALE)
      item = CreditNoteItem.new(fee_id: last_subscription_fee.id, precise_amount_cents:)
      taxes_result = CreditNotes::ApplyTaxesService.call(invoice: last_subscription_fee.invoice, items: [item])

      (
        precise_amount_cents -
        taxes_result.coupons_adjustment_amount_cents +
        taxes_result.taxes_amount_cents
      ).round
    end
  end
end
