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
              result.fees = fees.map do |fee|
                OpenStruct.new(
                  item_id: fee['item_id'],
                  item_code: fee['item_code'],
                  amount_cents: fee['amount_cents'],
                  tax_amount_cents: fee['tax_amount_cents'],
                  tax_breakdown: tax_breakdown(fee['tax_breakdown'])
                )
              end
            else
              code = body['failedInvoices'].first['validation_errors']['type']
              message = 'Service failure'

              deliver_tax_error_webhook(customer:, code:, message:)

              result.service_failure!(code:, message:)
            end
          end

          def process_void_response(body)
            invoice_id = body['succeededInvoices']&.first.try(:[], 'id')

            if invoice_id
              result.invoice_id = invoice_id
            else
              code = body['failedInvoices'].first['validation_errors']['type']
              message = 'Service failure'

              deliver_tax_error_webhook(customer:, code:, message:)

              result.service_failure!(code:, message:)
            end
          end

          def tax_breakdown(breakdown)
            breakdown.map do |b|
              if b['type'] == 'exempt'
                OpenStruct.new(
                  name: b['reason'],
                  rate: '0.00',
                  tax_amount: 0,
                  type: b['type']
                )
              else
                OpenStruct.new(
                  name: b['name'],
                  rate: b['rate'],
                  tax_amount: b['tax_amount'],
                  type: b['type']
                )
              end
            end
          end
        end
      end
    end
  end
end
