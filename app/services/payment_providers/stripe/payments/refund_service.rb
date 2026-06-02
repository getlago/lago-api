# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class RefundService < BaseService
        Result = BaseResult[:payment, :refund]

        def initialize(payment:, reason: nil)
          @payment = payment
          @reason = reason
          super
        end

        def call
          result.payment = payment

          stripe_result = create_stripe_refund
          refund = build_refund(
            amount_cents: stripe_result.amount,
            amount_currency: stripe_result.currency&.upcase,
            status: stripe_result.status,
            provider_refund_id: stripe_result.id
          )
          refund.save!

          result.refund = refund
          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        rescue ::Stripe::InvalidRequestError => e
          refund = build_refund(
            amount_cents: payment.amount_cents,
            amount_currency: payment.amount_currency,
            status: "failed",
            provider_refund_id: idempotency_key
          )
          refund.save!

          result.refund = refund
          result.service_failure!(code: "stripe_error", message: e.message)
        end

        private

        attr_reader :payment, :reason

        def create_stripe_refund
          ::Stripe::Refund.create(
            stripe_refund_payload,
            {
              api_key: payment.payment_provider.secret_key,
              idempotency_key:
            }
          )
        end

        def stripe_refund_payload
          {
            payment_intent: payment.provider_payment_id,
            amount: payment.amount_cents,
            reason: :requested_by_customer,
            metadata: {
              lago_customer_id: payment.customer_id,
              lago_refundable_id: refundable.id,
              lago_refundable_type: refundable.class.name,
              lago_payment_id: payment.id,
              lago_refund_reason: reason&.to_s
            }.compact
          }
        end

        def build_refund(amount_cents:, amount_currency:, status:, provider_refund_id:)
          Refund.new(
            organization_id: payment.organization_id,
            credit_note: nil,
            refundable:,
            reason:,
            payment:,
            payment_provider: payment.payment_provider,
            payment_provider_customer: payment.payment_provider_customer,
            amount_cents:,
            amount_currency:,
            status:,
            provider_refund_id:
          )
        end

        def refundable
          @refundable ||= payment.payable
        end

        def idempotency_key
          @idempotency_key ||= "payment-refund-#{payment.id}"
        end
      end
    end
  end
end
