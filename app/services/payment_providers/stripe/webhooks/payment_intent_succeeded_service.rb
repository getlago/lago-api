# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class PaymentIntentSucceededService < BaseService
        def call
          @result = update_payment_status! "succeeded"

          ::Payments::UpdatePaymentMethodDataJob.perform_later(
            provider_payment_id: event.data.object.id,
            provider_payment_method_id: event.data.object.payment_method
          )

          result
        end
      end
    end
  end
end
