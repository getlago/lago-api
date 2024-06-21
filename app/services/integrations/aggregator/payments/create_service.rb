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
          body = JSON.parse(response.body)

          if body.is_a?(Hash)
            process_hash_result(body)
          else
            process_string_result(body)
          end

          return result unless result.external_id

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

          raise e if e.error_code.to_i >= 500
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

        def payload
          Integrations::Aggregator::Payments::Payloads::Factory.new_instance(integration:, payment:).body
        end

        def process_hash_result(body)
          external_id = body['succeededPayment']&.first.try(:[], 'id')

          if external_id
            result.external_id = external_id
          else
            message = body['failedPayments'].first['validation_errors'].map { |error| error['Message'] }.join(". ")
            code = 'Validation error'

            deliver_error_webhook(customer:, code:, message:)
          end
        end

        def process_string_result(body)
          result.external_id = body
        end
      end
    end
  end
end
