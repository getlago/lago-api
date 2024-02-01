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
        return 0 if !minimum_commitment || invoice_subscription.first_period?

        fees_total_amount_cents = invoice_subscription.previous_invoice_subscription.total_amount_cents
        return 0 if fees_total_amount_cents >= commitment_amount_cents

        commitment_amount_cents - fees_total_amount_cents
      end

      # Calculated for previous period
  		def commitment_amount_cents
        previous_invoice_subscription = invoice_subscription.previous_invoice_subscription

        return 0 unless previous_invoice_subscription

        result = Commitments::CalculateAmountService.call(
          commitment: minimum_commitment,
          invoice_subscription: previous_invoice_subscription,
        )

        result.commitment_amount_cents
      end

      # TODO: refactor
      # def last_period?
      #   !subscription.active?
      # end
    end
  end
end
