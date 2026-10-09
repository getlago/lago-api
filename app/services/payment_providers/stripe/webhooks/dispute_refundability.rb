# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      # NOTE: refunds stay blocked while any dispute on the payment intent blocks them, and the
      #       disputes are read from stripe because webhooks can arrive out of order.
      module DisputeRefundability
        private

        def charge_refundable?
          if current_disputes.nil?
            event.data.object[:is_charge_refundable]
          else
            current_disputes.none? { |dispute| dispute[:is_charge_refundable] == false }
          end
        end

        def current_disputes
          return @current_disputes if defined?(@current_disputes)

          @current_disputes = if stripe_api_key.present?
            ::Stripe::Dispute.list(
              {payment_intent: provider_payment_id, limit: 100},
              {api_key: stripe_api_key}
            ).data
          end
        rescue *PaymentProviders::StripeProvider::PERMANENT_ERRORS => e
          Rails.logger.warn("Unable to list stripe disputes for #{provider_payment_id}: #{e.message}")
          @current_disputes = nil
        end

        def payment
          return @payment if defined?(@payment)

          # NOTE: a blank payment_intent would match manual payments, which store no provider id.
          @payment = if provider_payment_id.present?
            Payment.where(organization_id: organization.id).find_by(provider_payment_id:)
          end
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
