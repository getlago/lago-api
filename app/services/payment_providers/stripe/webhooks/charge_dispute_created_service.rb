# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class ChargeDisputeCreatedService < BaseService
        include DisputeRefundability

        def call
          return result unless payment

          # NOTE: `charge.dispute.created` also fires for inquiries, where stripe still accepts
          #       refunds. `is_charge_refundable` is the only reliable signal, and it flips
          #       through `charge.dispute.updated` when an inquiry escalates to a real dispute.
          if charge_refundable?
            ::Payments::CloseDisputeService.call(payment:)
          else
            ::Payments::OpenDisputeService.call(payment:, payment_refund_blocked_at:)
          end
        end

        private

        def payment_refund_blocked_at
          Time.zone.at(event.created)
        end
      end
    end
  end
end
