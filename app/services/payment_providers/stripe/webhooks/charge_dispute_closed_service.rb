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
          return result unless payment

          # NOTE: on a lost dispute the charge stays unrefundable, so the open flag is left in
          #       place and payment_dispute_lost_at takes over as the permanent refund block.
          ::Payments::CloseDisputeService.call(payment:) if event.data.object[:is_charge_refundable]

          if status == "lost"
            return ::Payments::LoseDisputeService.call(payment:, payment_dispute_lost_at:, reason:)
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
