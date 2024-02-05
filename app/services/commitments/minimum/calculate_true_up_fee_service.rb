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

      delegate :subscription, to: :invoice_subscription

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
        helper_service = Commitments::HelperService.new(
          commitment: minimum_commitment,
          invoice_subscription:,
          current_usage: true,
        )
        result = helper_service.period_invoice_ids

        charge_fees = Fee
          .charge_kind
          .joins(:charge)
          .where(
            subscription_id: subscription.id,
            invoice_id: result.period_invoice_ids,
            charge: { pay_in_advance: false },
          )

        subscription_fees = Fee
          .subscription_kind
          .joins(subscription: :plan)
          .where(
            subscription_id: subscription.id,
            invoice_id: result.period_invoice_ids,
            plan: { pay_in_advance: false },
          )

        charge_fees.sum(:amount_cents) + subscription_fees.sum(:amount_cents)
      end
    end
  end
end
