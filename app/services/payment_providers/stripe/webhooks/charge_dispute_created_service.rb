# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class ChargeDisputeCreatedService < BaseService
        include DisputeRefundability

        def call
          return result unless payment

          # NOTE: `created` also fires for inquiries, which leave the charge refundable.
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
