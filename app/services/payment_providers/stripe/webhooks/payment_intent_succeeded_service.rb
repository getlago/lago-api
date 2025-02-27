# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class PaymentIntentSucceededService < BaseService
        def call
          @result = update_payment_status! "succeeded"
          update_provider_payment_method_data
          result
        end

        private

        def update_provider_payment_method_data
          latest_charge = event.data.object.charges.data.last
          data = {
            id: event.data.object.payment_method,
            type: latest_charge.payment_method_details.type
          }
          if data[:type] == "card"
            data[:brand] = latest_charge.payment_method_details.card.brand
            data[:last4] = latest_charge.payment_method_details.card.last4
          end

          # NOTE: `result.payment was set by the service handling update_payment_status!
          result.payment.update(provider_payment_method_data: data)
        end
      end
    end
  end
end
