# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class PaymentIntentPaymentFailedService < BaseService
        def call
          result = update_payment_status! "failed"

          # NOTE: In case of 3DS failure, the checkout link becomes invalid so in lago, we'll create a new payment instead of a new link
          #       for the existing payment intent.
          if event.data.object.status == "requires_payment_method"
            PaymentProviders::Stripe::CancelPaymentIntentJob.perform_later(organization_id: organization.id, provider_payment_id: event.data.object.id)
          end

          result
        end
      end
    end
  end
end
