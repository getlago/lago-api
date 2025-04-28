# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class ChargeDisputeClosedService < BaseService
        def call
          status = event.data.object.status
          reason = event.data.object.reason
          provider_payment_id = event.data.object.payment_intent

          payment = Payment.find_by(provider_payment_id:)
          return result if !payment || !payment.payable.is_a?(Invoice)

          if status == "lost"
            return Invoices::LoseDisputeService.call(invoice: payment.payable, payment_dispute_lost_at:, reason:)
          end

          result
        end

        private

        def payment_dispute_lost_at
          Time.zone.at(event.created)
        end
      end
    end
  end
end
