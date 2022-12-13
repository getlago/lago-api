# frozen_string_literal: true

module CreditNotes
  class CreateFromUpgrade < BaseService
    def initialize(subscription:)
      @subscription = subscription

      super
    end

    def call
      return result if (last_subscription_fee&.amount_cents || 0).zero?

      amount = compute_amount
      return result unless amount.positive?

      vat_amount = (amount * last_subscription_fee.vat_rate).fdiv(100).ceil

      CreditNotes::CreateService.new(
        invoice: last_subscription_fee.invoice,
        credit_amount_cents: amount + vat_amount,
        refund_amount_cents: 0,
        items: [
          {
            fee_id: last_subscription_fee.id,
            amount_cents: amount,
          },
        ],
        reason: :order_change,
        automatic: true,
      ).call
    end

    private

    attr_accessor :subscription

    delegate :plan, :terminated_at, to: :subscription

    def last_subscription_fee
      @last_subscription_fee ||= subscription.fees.order(created_at: :desc).last
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

    def from_date
      date_service.previous_beginning_of_period(current_period: true)
    end

    def to_date
      date_service.next_end_of_period.to_date # TODO: deal with timezone
    end

    def day_price
      date_service.single_day_price(optional_from_date: from_date)
    end

    def remaining_duration
      billed_from = terminated_at.to_date

      if plan.has_trial? && subscription.trial_end_date >= billed_from
        billed_from = if subscription.trial_end_date > to_date
          to_date
        else
          subscription.trial_end_date
        end
      end

      (to_date - billed_from).to_i
    end
  end
end
