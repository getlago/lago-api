# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class PaymentIntentSucceededService < BaseService
        def call
          update_payment_status! "succeeded"
        end
      end
    end
  end
end
