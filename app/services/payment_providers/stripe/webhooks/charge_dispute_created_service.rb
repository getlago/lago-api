# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class ChargeDisputeCreatedService < BaseService
        def call
          return result unless payment

          if charge_refundable?
            ::Payments::CloseDisputeService.call(payment:)
          else
            ::Payments::OpenDisputeService.call(payment:, payment_refund_blocked_at:)
          end
        end

        private

        def payment
          return @payment if defined?(@payment)

          # NOTE: scoped to the organization, a stripe api key can be shared across several
          #       of them, and the dispute must not reach another organization's invoices.
          @payment = Payment.where(organization_id: organization.id)
            .find_by(provider_payment_id: event.data.object.payment_intent)
        end

        # NOTE: `charge.dispute.created` also fires for inquiries, where stripe still accepts
        #       refunds. `is_charge_refundable` is the only reliable signal, and it flips
        #       through `charge.dispute.updated` when an inquiry escalates to a real dispute.
        def charge_refundable?
          (current_dispute || event.data.object)[:is_charge_refundable]
        end

        # NOTE: stripe does not guarantee webhook ordering, so a replayed `created` delivered
        #       after the dispute closed would re-block refunds using stale data, and nothing
        #       would ever clear it again. Reading the dispute makes the transition order-safe.
        def current_dispute
          return @current_dispute if defined?(@current_dispute)
          return @current_dispute = nil if api_key.blank?

          @current_dispute = ::Stripe::Dispute.retrieve(event.data.object.id, {api_key:})
        rescue ::Stripe::InvalidRequestError, ::Stripe::AuthenticationError, ::Stripe::PermissionError => e
          # NOTE: retrying these never changes the answer, so fall back to the payload rather
          #       than dead-queueing the event. Transient errors are deliberately left to
          #       propagate: HandleEventJob retries them, and falling back to a possibly stale
          #       payload is what this lookup exists to prevent.
          Rails.logger.warn("Unable to retrieve stripe dispute #{event.data.object.id}: #{e.message}")
          @current_dispute = nil
        end

        def api_key
          payment.payment_provider&.secret_key
        end

        def payment_refund_blocked_at
          Time.zone.at(event.created)
        end
      end
    end
  end
end
