# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class BaseService < Integrations::Aggregator::BaseService
        def initialize(invoice:)
          @invoice = invoice

          super(integration:)
        end

        private

        attr_reader :invoice

        delegate :customer, to: :invoice, allow_nil: true

        def headers
          {
            'Connection-Id' => integration.connection_id,
            'Authorization' => "Bearer #{secret_key}",
            'Provider-Config-Key' => provider
          }
        end

        def integration
          return nil unless integration_customer

          integration_customer&.integration
        end

        def integration_customer
          @integration_customer ||= customer&.integration_customers&.first
        end

        def payload(type)
          Integrations::Aggregator::Invoices::Payloads::Factory.new_instance(
            integration_customer:,
            invoice:,
            type:
          ).body
        end
      end
    end
  end
end
