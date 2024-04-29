# frozen_string_literal: true

module V1
  module Integrations
    class CustomerErrorSerializer < ModelSerializer
      def serialize
        {
          lago_customer_id: model.id,
          external_customer_id: model.external_id,
          accounting_provider: options[:provider],
          provider_error: options[:provider_error],
        }
      end
    end
  end
end
