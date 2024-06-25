# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class BaseService < Integrations::Aggregator::BaseService
        def action_path
          "v1/#{provider}/contacts"
        end

        private

        def headers
          {
            'Connection-Id' => integration.connection_id,
            'Authorization' => "Bearer #{secret_key}",
            'Provider-Config-Key' => provider
          }
        end

        def deliver_success_webhook(customer:)
          SendWebhookJob.perform_later(
            'customer.accounting_provider_created',
            customer
          )
        end

        def process_hash_result(body)
          contact_id = body['succeededContacts']&.first.try(:[], 'id')

          if contact_id
            result.contact_id = contact_id
          else
            message = body['failedContacts'].first['validation_errors'].map { |error| error['Message'] }.join(". ")
            code = 'Validation error'

            deliver_error_webhook(customer:, code:, message:)
          end
        end

        def process_string_result(body)
          result.contact_id = body
        end
      end
    end
  end
end
