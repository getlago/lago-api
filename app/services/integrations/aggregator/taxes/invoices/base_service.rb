# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class BaseService < Integrations::Aggregator::BaseService
          def initialize(invoice:, fees: nil)
            @invoice = invoice
            @fees = fees || invoice.fees

            super(integration:)
          end

          private

          attr_reader :invoice, :fees

          delegate :customer, to: :invoice, allow_nil: true

          def integration
            return nil unless integration_customer

            integration_customer&.integration
          end

          def integration_customer
            @integration_customer ||=
              customer
                .integration_customers
                .where(type: 'IntegrationCustomers::AnrokCustomer')
                .first
          end

          def headers
            {
              'Connection-Id' => integration.connection_id,
              'Authorization' => "Bearer #{secret_key}",
              'Provider-Config-Key' => provider_key
            }
          end

          def process_response(body)
            fees = body['succeededInvoices']&.first.try(:[], 'fees')

            if fees
              result.fees = fees
            else
              code = body['failedInvoices'].first['validation_errors']['type']
              message = 'Service failure'

              result.service_failure!(code:, message:)
            end
          end
        end
      end
    end
  end
end
