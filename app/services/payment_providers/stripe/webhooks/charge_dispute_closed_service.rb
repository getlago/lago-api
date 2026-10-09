# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class ChargeDisputeClosedService < BaseService
        include DisputeRefundability

        def call
          return result unless payment

          if event.data.object.status == "lost"
            return ::Payments::LoseDisputeService.call(
              payment:,
              payment_dispute_lost_at:,
              reason: event.data.object.reason
            )
          end

          if charge_refundable?
            ::Payments::CloseDisputeService.call(payment:)
          else
            result
          end
        end

        private

        def payment_dispute_lost_at
          Time.zone.at(event.created)
        end
      end
    end
  end
end
