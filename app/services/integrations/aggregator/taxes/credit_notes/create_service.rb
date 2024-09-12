# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module CreditNotes
        class CreateService < Integrations::Aggregator::Taxes::BaseService
          def initialize(credit_note:)
            @credit_note = credit_note

            super(integration:)
          end

          def action_path
            "v1/#{provider}/finalized_invoices"
          end

          def call
            return result unless integration
            return result unless integration.type == 'Integrations::AnrokIntegration'

            response = http_client.post_with_response(payload, headers)
            body = JSON.parse(response.body)

            process_response(body)
            assign_external_customer_id

            result
          rescue LagoHttpClient::HttpError => e
            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          end

          private

          attr_reader :credit_note

          delegate :customer, to: :credit_note, allow_nil: true

          def payload
            Integrations::Aggregator::Taxes::CreditNotes::Payload.new(
              integration:,
              customer:,
              integration_customer:,
              credit_note:
            ).body
          end
        end
      end
    end
  end
end
