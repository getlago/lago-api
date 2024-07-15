# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class UpdateService < BaseService
        def initialize(integration:, integration_customer:)
          @integration_customer = integration_customer

          super(integration:)
        end

        def call
          response = http_client.put_with_response(params, headers)
          body = JSON.parse(response.body)

          if body.is_a?(Hash)
            process_hash_result(body)
          else
            process_string_result(body)
          end

          return result unless result.contact_id

          deliver_success_webhook(customer:)

          result
        rescue LagoHttpClient::HttpError => e
          code = code(e)
          message = message(e)

          deliver_error_webhook(customer:, code:, message:)

          result.service_failure!(code:, message:)
        end

        private

        attr_reader :integration_customer, :subsidiary_id

        delegate :customer, to: :integration_customer

        def params
          Integrations::Aggregator::Contacts::Payloads::Factory.new_instance(
            integration:,
            integration_customer:,
            customer:,
            subsidiary_id:
          ).update_body
        end
      end
    end
  end
end
