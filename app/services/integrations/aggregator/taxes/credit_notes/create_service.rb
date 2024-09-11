# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module CreditNotes
        class CreateService < Integrations::Aggregator::Taxes::Invoices::BaseService
          def initialize(credit_note:)
            @credit_note = credit_note

            super(invoice: credit_note.invoice)
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

          def payload
            [
              {
                'id' => "cn_#{credit_note.id}",
                'issuing_date' => credit_note.issuing_date,
                'currency' => credit_note.currency,
                'contact' => {
                  'external_id' => integration_customer&.external_customer_id || customer.external_id,
                  'name' => customer.name,
                  'address_line_1' => customer.shipping_address_line1 || customer.address_line1,
                  'city' => customer.shipping_city || customer.city,
                  'zip' => customer.shipping_zipcode || customer.zipcode,
                  'country' => customer.shipping_country || customer.country,
                  'taxable' => customer.tax_identification_number.present?,
                  'tax_number' => customer.tax_identification_number
                },
                'fees' => credit_note.items.order(created_at: :asc).map { |item| cn_item(item) }
              }
            ]
          end

          def cn_item(item)
            fee = item.fee
            base_payload = Integrations::Aggregator::BasePayload.new(integration:)

            mapped_item = if fee.charge?
              base_payload.billable_metric_item(fee)
            elsif fee.add_on_id.present?
              base_payload.add_on_item(fee)
            elsif fee.commitment?
              base_payload.commitment_item
            elsif fee.subscription?
              base_payload.subscription_item
            end
            mapped_item ||= OpenStruct.new

            {
              'item_id' => fee.item_id,
              'item_code' => mapped_item.external_id,
              'amount_cents' => (fee.sub_total_excluding_taxes_amount_cents&.to_i || 0) * -1
            }
          end
        end
      end
    end
  end
end
