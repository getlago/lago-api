# frozen_string_literal: true

module Integrations
  module Aggregator
    module CreditNotes
      class CreateService < Integrations::Aggregator::Invoices::BaseService
        def initialize(credit_note:)
          @credit_note = credit_note

          super(invoice:)
        end

        def action_path
          "v1/#{provider}/creditnotes"
        end

        def call
          return result unless integration
          return result unless integration.sync_credit_notes
          return result unless credit_note.finalized?

          response = http_client.post_with_response(payload, headers)
          result.external_id = JSON.parse(response.body)

          IntegrationResource.create!(
            integration:,
            external_id: result.external_id,
            syncable_id: credit_note.id,
            syncable_type: 'CreditNote',
            resource_type: :credit_note
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
          return result.not_found_failure!(resource: 'credit_note') unless credit_note

          ::Integrations::Aggregator::CreditNotes::CreateJob.perform_later(credit_note:)

          result.credit_note_id = credit_note.id
          result
        end

        private

        attr_reader :credit_note

        delegate :customer, :invoice, to: :credit_note, allow_nil: true

        def payload
          Integrations::Aggregator::CreditNotes::Payloads::BasePayload.new(
            integration:,
            integration_customer:,
            credit_note:
          ).body
        end
      end
    end
  end
end
