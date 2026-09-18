# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      # NOTE: refundability belongs to the charge, not to a single dispute: a payment intent can
      #       carry several disputes, and refunds stay blocked while any one of them blocks them.
      #       Reading the current set also makes the transition order-safe, since stripe does not
      #       guarantee webhook ordering and a replayed event would otherwise apply stale state.
      module DisputeRefundability
        private

        def charge_refundable?
          return event.data.object[:is_charge_refundable] if current_disputes.nil?

          current_disputes.none? { |dispute| dispute[:is_charge_refundable] == false }
        end

        def current_disputes
          return @current_disputes if defined?(@current_disputes)
          return @current_disputes = nil if stripe_api_key.blank?

          @current_disputes = ::Stripe::Dispute.list(
            {payment_intent: provider_payment_id, limit: 100},
            {api_key: stripe_api_key}
          ).data
        rescue ::Stripe::InvalidRequestError, ::Stripe::AuthenticationError, ::Stripe::PermissionError => e
          # NOTE: retrying these never changes the answer, so fall back to the payload rather
          #       than dead-queueing the event. Transient errors are deliberately left to
          #       propagate: HandleEventJob retries them, and acting on a possibly stale payload
          #       is what this lookup exists to prevent.
          Rails.logger.warn("Unable to list stripe disputes for #{provider_payment_id}: #{e.message}")
          @current_disputes = nil
        end

        def payment
          return @payment if defined?(@payment)

          # NOTE: scoped to the organization, a stripe api key can be shared across several
          #       of them, and the dispute must not reach another organization's invoices.
          @payment = Payment.where(organization_id: organization.id).find_by(provider_payment_id:)
        end

        def provider_payment_id
          event.data.object.payment_intent
        end

        def stripe_api_key
          payment&.payment_provider&.secret_key
        end
      end
    end
  end
end
