# frozen_string_literal: true

module Integrations
  module Aggregator
    module Payments
      class CreateService < Integrations::Aggregator::Invoices::BaseService
        def initialize(payment:)
          @payment = payment

          super(invoice:)
        end

        def action_path
          "v1/#{provider}/payments"
        end

        def call
          return result unless integration
          return result unless integration.sync_payments
          return result unless invoice.finalized?

          response = http_client.post_with_response(payload, headers)
          result.external_id = JSON.parse(response.body)

          IntegrationResource.create!(
            integration:,
            external_id: result.external_id,
            syncable_id: payment.id,
            syncable_type: 'Payment',
            resource_type: :payment
          )

          result
        rescue LagoHttpClient::HttpError => e
          error = e.json_message
          code = error['type']
          message = error.dig('payload', 'message')

          deliver_error_webhook(customer:, code:, message:)

          raise e
        end

        def call_async
          return result.not_found_failure!(resource: 'payment') unless payment

          ::Integrations::Aggregator::Payments::CreateJob.perform_later(payment:)

          result.payment_id = payment.id
          result
        end

        private

        attr_reader :payment

        delegate :customer, :invoice, to: :payment, allow_nil: true

        def integration_invoice
          invoice.integration_resources.where(resource_type: 'invoice', syncable_type: 'Invoice').first
        end

        def payload
          {
            'type' => 'customerpayment',
            'isDynamic' => true,
            'columns' => {
              'customer' => integration_customer.external_customer_id
            },
            'lines' => [
              {
                'sublistId' => 'apply',
                'lineItems' => [
                  {
                    # If the invoice is not synced yet, lets raise an error and retry. (doc: nil is an invalid request)
                    'doc' => integration_invoice&.external_id,
                    'apply' => true,
                    'amount' => amount(payment.amount_cents, resource: invoice)
                  }
                ]
              }
            ],
            'options' => {
              'ignoreMandatoryFields' => false
            }
          }
        end
      end
    end
  end
end
