# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class PaymentIntentSucceededService < BaseService
        def call
          @result = update_payment_status! "succeeded"

          payment = Payment.find_by(provider_payment_id: event.data.object.id)
          if payment
            ::Payments::UpdatePaymentMethodDataService.call!(
              payment:,
              payment_method_id: event.data.object.payment_method
            )
          end

          result
        end
      end
    end
  end
end
