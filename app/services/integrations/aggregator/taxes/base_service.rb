# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      class BaseService < Integrations::Aggregator::BaseService
        SPECIAL_TAXATION_TYPES = %w[exempt notCollecting productNotTaxed jurisNotTaxed jurisHasNoTax].freeze
        def initialize(invoice: nil, fees: nil, credit_note: nil, items: nil)
          @invoice = invoice
          @credit_note = credit_note
          @fees = fees || invoice&.fees
          @items = items || credit_note&.items

          super(integration:)
        end

        private

        attr_reader :invoice, :fees, :credit_note, :items

        def payload_service
          @payload_service ||= Integrations::Aggregator::Taxes::PayloadBuilder.assign(
            integration:, customer:, invoice: nil, integration_customer:, fees: [], credit_note: nil, items: []
          )
        end

        def customer
          if invoice.present
            invoice.customer
          else
            credit_note.customer
          end
        end

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
            code, message = retrieve_error_details(body['failedInvoices'].first['validation_errors'])
            deliver_tax_error_webhook(customer:, code:, message:)

            result.service_failure!(code:, message:)
          end
        end

        def process_void_response(body)
          invoice_id = body['succeededInvoices']&.first.try(:[], 'id')

          if invoice_id
            result.invoice_id = invoice_id
          else
            code, message = retrieve_error_details(body['failedInvoices'].first['validation_errors'])
            deliver_tax_error_webhook(customer:, code:, message:)

            result.service_failure!(code:, message:)
          end
        end

        def tax_breakdown(breakdown)
          breakdown.map do |b|
            if SPECIAL_TAXATION_TYPES.include?(b['type'])
              OpenStruct.new(
                name: humanize_tax_name(b['reason'].presence || b['type']),
                rate: '0.00',
                tax_amount: 0,
                type: b['type']
              )
            elsif b['rate']
              OpenStruct.new(
                name: b['name'],
                rate: b['rate'],
                tax_amount: b['tax_amount'],
                type: b['type']
              )
            else
              OpenStruct.new(
                name: humanize_tax_name(b['reason'].presence || b['type'] || 'unknown_taxation'),
                rate: '0.00',
                tax_amount: 0,
                type: b['type'] || 'unknown_taxation'
              )
            end
          end
        end

        def retrieve_error_details(validation_error)
          if validation_error.is_a?(Hash)
            code = validation_error['type']
            message = 'Service failure'
            return [code, message]
          end

          code = 'validationError'
          message = validation_error
          [code, message]
        end

        def humanize_tax_name(camelized_name)
          camelized_name.underscore.humanize
        end
      end
    end
  end
end
