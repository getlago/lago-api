# frozen_string_literal: true

module PaymentProviders
  module Webhooks
    module Stripe
      class ChargeDisputeClosedService < BaseService
        def call
          status = event.data.object.status
          reason = event.data.object.reason
          provider_payment_id = event.data.object.payment_intent

          payment = Payment.find_by(provider_payment_id:)
          return result.not_found_failure!(resource: 'stripe_payment') unless payment

          if status == 'lost'
            return Invoices::LoseDisputeService.call(invoice: payment.invoice, payment_dispute_lost_at:, reason:)
          end

          result
        end

        private

        def event
          @event ||= ::Stripe::Event.construct_from(JSON.parse(event_json))
        end

        def payment_dispute_lost_at
          Time.zone.at(event.created)
        end
      end
    end
  end
end
