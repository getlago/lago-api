# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class ChargeDisputeClosedService < BaseService
        include DisputeRefundability

        def call
          return result unless payment

          # NOTE: unblock only once no dispute on the payment blocks refunds any more. On a lost
          #       dispute the charge stays unrefundable, and payment_dispute_lost_at takes over
          #       as the permanent refund block.
          ::Payments::CloseDisputeService.call(payment:) if charge_refundable?

          if event.data.object.status == "lost"
            return ::Payments::LoseDisputeService.call(
              payment:,
              payment_dispute_lost_at:,
              reason: event.data.object.reason
            )
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
