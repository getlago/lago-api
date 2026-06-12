# frozen_string_literal: true

module PaymentProviders
  module Gocardless
    module Payments
      class UpdateReferenceService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment
          super
        end

        def call
          result.payment = payment
          return result if payment.provider_payment_id.blank?
          return result unless payment.payable.is_a?(Invoice)
          return result if invoice.number.blank?

          client.payments.update(
            payment.provider_payment_id,
            params: {metadata: {lago_invoice_number: invoice.number}}
          )

          result
        rescue GoCardlessPro::Error => e
          # Best-effort. The invoice has already been finalized and the
          # subscription has already activated; updating the PSP-side
          # reference is presentation polish, not correctness. Log a warning
          # and return success so the caller never blocks on this.
          Rails.logger.warn(
            "PaymentProviders::Gocardless::Payments::UpdateReferenceService: " \
            "failed to update GoCardless payment #{payment.provider_payment_id} " \
            "for payment #{payment.id}: #{e.message}"
          )
          result
        end

        private

        attr_reader :payment

        def client
          @client ||= GoCardlessPro::Client.new(
            access_token: payment.payment_provider.access_token,
            environment: payment.payment_provider.environment
          )
        end

        def invoice
          @invoice ||= payment.payable
        end
      end
    end
  end
end
