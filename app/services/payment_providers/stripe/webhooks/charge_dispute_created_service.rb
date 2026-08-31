# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class ChargeDisputeCreatedService < BaseService
        def call
          provider_payment_id = event.data.object.payment_intent

          payment = Payment.where(organization_id: organization.id).find_by(provider_payment_id:)
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

        def charge_refundable?
          event.data.object[:is_charge_refundable]
        end

        def payment_refund_blocked_at
          Time.zone.at(event.created)
        end
      end
    end
  end
end
