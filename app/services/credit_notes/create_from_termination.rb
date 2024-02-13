# frozen_string_literal: true

module CreditNotes
  class CreateFromTermination < BaseService
    def initialize(subscription:, reason: 'order_change', upgrade: false)
      @subscription = subscription
      @reason = reason
      @upgrade = upgrade

      super
    end

    def call
      return result if (last_subscription_fee&.amount_cents || 0).zero? || last_subscription_fee.invoice.voided?

      amount = compute_amount
      return result unless amount.positive?

      # NOTE: if credit notes were already issued on the fee,
      #       we have to deduct them from the prorated amount
      amount -= last_subscription_fee.credit_note_items.sum(:amount_cents)
      return result unless amount.positive?

      CreditNotes::CreateService.new(
        invoice: last_subscription_fee.invoice,
        credit_amount_cents: creditable_amount_cents(amount),
        refund_amount_cents: 0,
        items: [
          {
            fee_id: last_subscription_fee.id,
            amount_cents: amount.truncate(CreditNote::DB_PRECISION_SCALE),
          },
        ],
        reason: reason.to_sym,
        automatic: true,
      ).call
    end

    private

    attr_accessor :subscription, :reason, :upgrade

    delegate :plan, :terminated_at, :customer, to: :subscription

    def last_subscription_fee
      @last_subscription_fee ||= subscription.fees.subscription.order(created_at: :desc).first
    end

    def compute_amount
      day_price * remaining_duration
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        terminated_at,
      )
    end

    def to_date
      date_service.next_end_of_period.to_date
    end

    def day_price
      date_service.single_day_price
    end

    def terminated_at_in_timezone
      terminated_at.in_time_zone(customer.applicable_timezone)
    end

    def remaining_duration
      billed_from = terminated_at_in_timezone.end_of_day.utc.to_date
      billed_from = billed_from - 1.day if upgrade

      if plan.has_trial? && subscription.trial_end_date >= billed_from
        billed_from = if subscription.trial_end_date > to_date
          to_date
        else
          subscription.trial_end_date
        end
      end

      duration = (to_date - billed_from).to_i

      duration < 0 ? 0 : duration
    end

    def creditable_amount_cents(item_amount)
      taxes_result = CreditNotes::ApplyTaxesService.call(
        invoice: last_subscription_fee.invoice,
        items: [
          CreditNoteItem.new(
            fee_id: last_subscription_fee.id,
            precise_amount_cents: item_amount.truncate(CreditNote::DB_PRECISION_SCALE),
          ),
        ],
      )

      (
        item_amount.truncate(CreditNote::DB_PRECISION_SCALE) -
        taxes_result.coupons_adjustment_amount_cents +
        taxes_result.taxes_amount_cents
      ).round
    end
  end
end
