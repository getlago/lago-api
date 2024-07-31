# frozen_string_literal: true

module V1
  module Integrations
    module Taxes
      class FeeErrorSerializer < ModelSerializer
        def serialize
          {
            lago_integration_id: model.id,
            tax_provider_code: model.code,
            lago_charge_id: options[:lago_charge_id],
            event_transaction_id: options[:event_transaction_id],
            provider_error: options[:provider_error]
          }
        end
      end
    end
  end
end
