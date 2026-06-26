# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module PaymentProviders
  module Stripe
    module Webhooks
      class PaymentIntentPaymentFailedService < BaseService
        def call
          update_payment_status! "failed"
        end
      end
    end
  end
end
