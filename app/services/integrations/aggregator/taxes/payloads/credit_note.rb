# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Payloads
        class CreditNote < BasePayload
          def initialize(integration:, customer:, credit_note:, integration_customer:, items: [])
            super(integration:)

            @customer = customer
            @integration_customer = integration_customer
            @credit_note = credit_note
            @items = (items.is_a?(Array) || !items&.first&.persisted?) ? items : items.order(created_at: :asc)
          end

          def create_service_payload
            data = body.first
            data['id'] = "cr_#{credit_note.id}"

            [data]
          end

          def create_draft_payload
            body
          end

          def negate_service_payload
            [
              {
                'id' => "cr_#{credit_card.id}",
                'voided_id' => "cr_#{credit_card.id}_voided"
              }
            ]
          end

          def void_service_payload
            [
              {
                'id' => "cr_#{credit_note.id}"
              }
            ]
          end

          private

          attr_reader :customer, :integration_customer, :credit_note, :items
          def body
            [
              {
                'issuing_date' => credit_note.issuing_date,
                'currency' => credit_note.total_amount_currency,
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
                'fees' => items.map { |item| payload_item(item) }
              }
            ]
          end

          def payload_item(item)
            mapped_item = if item.charge?
                            billable_metric_item(item)
                          elsif item.add_on_id.present?
                            add_on_item(item)
                          elsif item.commitment?
                            commitment_item
                          elsif item.subscription?
                            subscription_item
                          end
            mapped_item ||= empty_struct

            {
              'item_id' => item.item_id,
              'item_code' => mapped_item.external_id,
              'amount_cents' => 0 - item.sub_total_excluding_taxes_amount_cents&.to_i
            }
          end

          def empty_struct
            @empty_struct ||= OpenStruct.new
          end
        end
      end
    end
  end
end
