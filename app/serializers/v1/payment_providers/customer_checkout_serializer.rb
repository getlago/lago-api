# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  module PaymentProviders
    class CustomerCheckoutSerializer < ModelSerializer
      def serialize
        {
          lago_customer_id: model.id,
          external_customer_id: model.external_id,
          payment_provider: model.payment_provider,
          payment_provider_code: model.payment_provider_code,
          checkout_url: options[:checkout_url]
        }
      end
    end
  end
end
