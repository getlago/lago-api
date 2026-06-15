# frozen_string_literal: true

module PaymentProviders
  module Adyen
    module Payments
      class UpdateReferenceService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment
          super
        end

        def call
          result.payment = payment

          # Adyen treats merchantReference and additionalData on a captured
          # payment as immutable. The Ruby SDK's ModificationsApi exposes
          # state-changing endpoints only (refund, cancel, capture, reverse,
          # update_authorised_amount) — no surface for amending a captured
          # payment's reference or metadata after the fact. The dive-in for
          # the PSP reference update flagged this as something to verify at
          # implementation time and defined a log-only fallback; we are on
          # that fallback path until/unless Adyen ships such an API.
          #
          # Operators reconciling Adyen-side payments after a gated
          # subscription activation will continue to see the placeholder
          # reference Lago set at payment-creation time. Manual reconciliation
          # via the Lago payment id (already in additionalData metadata at
          # creation) remains the workaround.
          Rails.logger.info(
            "PaymentProviders::Adyen::Payments::UpdateReferenceService: " \
            "Adyen does not support updating captured payment references; " \
            "skipping payment #{payment.id}"
          )

          result
        end

        private

        attr_reader :payment
      end
    end
  end
end
