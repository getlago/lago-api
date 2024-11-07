# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class BaseService < Integrations::Aggregator::BaseService
        def initialize(invoice:, send_webhook: false)
          @invoice = invoice
          @send_webhook = send_webhook
          super(integration:)
        end

        private

        attr_reader :invoice, :send_webhook

        delegate :customer, to: :invoice, allow_nil: true

        def headers
          {
            'Connection-Id' => integration.connection_id,
            'Authorization' => "Bearer #{secret_key}",
            'Provider-Config-Key' => provider_key
          }
        end

        def integration
          return nil unless integration_customer

          integration_customer&.integration
        end

        def integration_customer
          @integration_customer ||= customer&.integration_customers&.accounting_kind&.first
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
