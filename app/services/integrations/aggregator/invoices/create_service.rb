# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateService < BaseService
        def action_path
          "v1/#{provider}/invoices"
        end

        def call
          return result unless integration
          return result unless integration.sync_invoices
          return result unless invoice.finalized?
          return result if payload.integration_invoice

          throttle!(:anrok, :netsuite, :xero)

          response = http_client.post_with_response(payload.body, headers)
          body = JSON.parse(response.body)

          external_id = if body.is_a?(Hash)
            process_hash_result(body)
          else
            body
          end

          Rails.logger.info "Response body: #{body}"
          Rails.logger.info "External ID: #{external_id}"

          return result unless external_id

          Rails.logger.info "Creating integration resource with external ID: #{external_id}"

          IntegrationResource.create!(
            integration:,
            external_id: external_id,
            syncable_id: invoice.id,
            syncable_type: 'Invoice',
            resource_type: :invoice
          )

          Rails.logger.info "Integration resource created. external ID: #{external_id}, invoice ID: #{invoice.id}"

          result.external_id = external_id
          result
        rescue LagoHttpClient::HttpError => e
          raise RequestLimitError(e) if request_limit_error?(e)

          code = code(e)
          message = message(e)

          deliver_error_webhook(customer:, code:, message:)

          return result if e.error_code.to_i < 500

          raise e
        rescue Integrations::Aggregator::BasePayload::Failure => e
          deliver_error_webhook(customer:, code: e.code, message: e.code.humanize)
          result
        end

        def call_async
          return result.not_found_failure!(resource: 'invoice') unless invoice

          ::Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:)

          result.invoice_id = invoice.id
          result
        end

        private

        def process_hash_result(body)
          external_id = body['succeededInvoices']&.first.try(:[], 'id')

          return external_id if external_id

          message = body['failedInvoices'].first['validation_errors'].map { |error| error['Message'] }.join(". ")
          code = 'Validation error'

          deliver_error_webhook(customer:, code:, message:)

          nil
        end
      end
    end
  end
end
