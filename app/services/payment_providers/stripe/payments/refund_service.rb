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

          # TODO(M4-webhooks): emit `payment.refunded` outbound webhook once the
          # webhook services land.
          result.refund = refund
          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        rescue ::Stripe::InvalidRequestError => e
          # Stripe rejected the refund (e.g. charge already refunded, charge not
          # refundable). We persist a Refund row in `failed` state so the dispatcher's
          # "skip if refund already exists" idempotency guard stops further attempts.
          # The provider_refund_id column is NOT NULL, but there's no PSP refund id
          # to record here — Stripe never created one. Use the Lago-side idempotency
          # key as a sentinel: it's unique per payment and clearly not a Stripe id
          # shape, so lookups by it can't collide with a real refund.
          refund = build_refund(
            amount_cents: payment.amount_cents,
            amount_currency: payment.amount_currency,
            status: "failed",
            provider_refund_id: idempotency_key
          )
          refund.save!

          # TODO(M4-webhooks): emit `payment.refund_failure` outbound webhook
          # carrying the PSP message + code, and produce a `payment.refund_failure`
          # activity log entry. Both land once the webhook services exist.
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
