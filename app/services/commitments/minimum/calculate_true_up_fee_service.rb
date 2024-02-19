# frozen_string_literal: true

module Commitments
  module Minimum
    class CalculateTrueUpFeeService < BaseService
      def self.new_instance(invoice_subscription:)
        klass = if invoice_subscription.subscription.plan.pay_in_advance?
          Commitments::Minimum::InAdvance::CalculateTrueUpFeeService
        else
          Commitments::Minimum::InArrears::CalculateTrueUpFeeService
        end

        klass.new(invoice_subscription:)
      end

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
        helper_service = Commitments::HelperService.new_instance(
          commitment: minimum_commitment,
          invoice_subscription:,
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

        dates_service = helper_service.dates_service
        charge_in_advance_fees = Fee
          .charge_kind
          .joins(:charge)
          .where(
            subscription_id: subscription.id,
            charge: { pay_in_advance: true },
          )
          .where(
            "(fees.properties->>'charges_from_datetime')::timestamptz = ?",
            dates_service.previous_beginning_of_period&.iso8601(3),
          )
          .where(
            "(fees.properties->>'charges_to_datetime')::timestamptz = ?",
            dates_service.end_of_period&.iso8601(3),
          )

        charge_fees.sum(:amount_cents) +
          subscription_fees.sum(:amount_cents) +
          charge_in_advance_fees.sum(:amount_cents)
      end
    end
  end
end
