# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      # Asks Stripe what the intent is doing right now, rather than trusting `provider_payment_data`,
      # which is a snapshot taken when the intent was created and never refreshed afterwards.
      #
      # A payment is only an abandoned authentication challenge when the live intent is still
      # waiting on the customer, on a card. `requires_action` on its own is not enough: it also
      # covers an incoming wire, ACH microdeposits and offline vouchers, none of which are card
      # payments and all of which must be left to arrive.
      class CheckAbandonedAuthenticationService < BaseService
        AUTHENTICATION_NEXT_ACTIONS = %w[use_stripe_sdk redirect_to_url].freeze

        Result = BaseResult[:abandoned]

        def initialize(payment:)
          @payment = payment
          super
        end

        def call
          result.abandoned = false
          return result if payment.provider_payment_id.blank?

          result.abandoned = abandoned?(payment_intent)
          result
        rescue ::Stripe::InvalidRequestError => e
          # The intent cannot be read, so we cannot claim it was abandoned. Leaving it alone keeps
          # the invoice locked, which is the outcome we already have today.
          Rails.logger.info("Stripe payment intent unreadable for payment #{payment.id}: #{e.message}")
          result
        end

        private

        attr_reader :payment

        def payment_intent
          ::Stripe::PaymentIntent.retrieve(
            {id: payment.provider_payment_id, expand: ["payment_method"]},
            {api_key: payment.payment_provider.secret_key}
          )
        end

        def abandoned?(intent)
          intent.status == "requires_action" &&
            intent.payment_method&.type == "card" &&
            AUTHENTICATION_NEXT_ACTIONS.include?(intent.next_action&.type)
        end
      end
    end
  end
end
