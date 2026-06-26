# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module PaymentProviders
  module Stripe
    module Webhooks
      class PaymentIntentSucceededService < BaseService
        def call
          @result = update_payment_status! "succeeded"

          if result.payment
            ::Payments::SetPaymentMethodAndCreateReceiptJob.perform_later(
              payment: result.payment,
              provider_payment_method_id: event.data.object.payment_method
            )
          end

          result
        end
      end
    end
  end
end
