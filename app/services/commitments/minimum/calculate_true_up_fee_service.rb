# frozen_string_literal: true

module Commitments
  module Minimum
    class CalculateTrueUpFeeService < BaseService
      def initialize(invoice_subscription:)
        @invoice_subscription = invoice_subscription
        @minimum_commitment = invoice_subscription.subscription.plan.minimum_commitment

        super
      end

      def call
        result.amount_cents = amount_cents
        result
      end

      private

      attr_reader :minimum_commitment, :invoice_subscription

      def amount_cents
        return 0 if !minimum_commitment || fees_total_amount_cents >= commitment_amount_cents

        commitment_amount_cents - fees_total_amount_cents
      end

  		def commitment_amount_cents
        result = Commitments::CalculateAmountService.call(
          commitment: minimum_commitment,
          invoice_subscription:,
        )

        result.commitment_amount_cents
      end

      def fees_total_amount_cents
        # TODO: in case if it's billed monthly, yearly plan
        # we need to select all the invoice_subscriptions for the whole year not just
        # one invoice_subscription (fees table)

        charge_fees = invoice_subscription
          .fees
          .charge_kind
          .joins(:charge)
          .where(charge: { pay_in_advance: false })

        subscription_fees = invoice_subscription
          .fees
          .subscription_kind
          .joins(subscription: :plan)
          .where(plan: { pay_in_advance: false })

        charge_fees.sum(:amount_cents) + subscription_fees.sum(:amount_cents)
      end
    end
  end
end
