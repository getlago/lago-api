# frozen_string_literal: true

module Integrations
  module Aggregator
    module CreditNotes
      class CreateService < BaseService
        def initialize(credit_note:)
          @credit_note = credit_note

          super(integration:)
        end

        def action_path
          "v1/#{provider}/creditnotes"
        end

        def call
          return result unless integration
          return result unless integration.sync_credit_notes
          return result unless credit_note.finalized?
          return result unless fallback_item

          response = http_client.post_with_response(payload, headers)
          result.external_id = JSON.parse(response.body)

          IntegrationResource.create!(
            integration:,
            external_id: result.external_id,
            syncable_id: credit_note.id,
            syncable_type: 'CreditNote',
            resource_type: :credit_note,
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

        delegate :customer, to: :credit_note, allow_nil: true

        def headers
          {
            'Connection-Id' => integration.connection_id,
            'Authorization' => "Bearer #{secret_key}",
            'Provider-Config-Key' => provider
          }
        end

        def integration
          return nil unless integration_customer

          integration_customer&.integration
        end

        def integration_customer
          @integration_customer ||= customer&.integration_customers&.first
        end

        def billable_metric_item(fee)
          integration
            .integration_mappings
            .find_by(mappable_type: 'BillableMetric', mappable_id: fee.billable_metric.id) || fallback_item
        end

        def add_on_item(fee)
          integration
            .integration_mappings
            .find_by(mappable_type: 'AddOn', mappable_id: fee.add_on.id) || fallback_item
        end

        def item(fee)
          mapped_item = if fee.charge?
            billable_metric_item(fee)
          elsif fee.add_on?
            add_on_item(fee)
          elsif fee.credit?
            credit_item
          elsif fee.commitment?
            commitment_item
          elsif fee.subscription?
            subscription_item
          end

          {
            'item' => mapped_item.external_id,
            'account' => mapped_item.external_account_code,
            'quantity' => fee.units,
            'rate' => fee.precise_unit_amount
          }
        end

        def coupons
          output = []

          if credit_note.coupons_adjustment_amount_cents > 0
            output << {
              'item' => coupon_item.external_id,
              'account' => coupon_item.external_account_code,
              'quantity' => 1,
              'rate' => -amount(credit_note.coupons_adjustment_amount_cents, resource: credit_note)
            }
          end

          output
        end

        def payload
          {
            'type' => 'creditmemo',
            'isDynamic' => true,
            'columns' => {
              'tranid' => credit_note.number,
              'entity' => integration_customer.external_customer_id,
              'istaxable' => true,
              'taxitem' => tax_item.external_id,
              'taxamountoverride' => amount(credit_note.taxes_amount_cents, resource: credit_note),
              'otherrefnum' => credit_note.number,
              'custbody_lago_id' => credit_note.id,
              'tranId' => credit_note.id
            },
            'lines' => [
              {
                'sublistId' => 'item',
                'lineItems' => credit_note.items.map { |item| item(item.fee) } + coupons
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
