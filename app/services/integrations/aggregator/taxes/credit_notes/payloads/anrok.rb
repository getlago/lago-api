# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module CreditNotes
        module Payloads
          class Anrok < BasePayload
            def initialize(integration:, customer:, integration_customer:, credit_note:)
              super(integration:, billing_entity: customer.billing_entity)

              @customer = customer
              @integration_customer = integration_customer
              @credit_note = credit_note
            end

            def body
              shipping = customer.effective_shipping_address

              [
                {
                  "id" => "cn_#{credit_note.id}",
                  "issuing_date" => credit_note.issuing_date,
                  "currency" => credit_note.currency,
                  "contact" => {
                    "external_id" => integration_customer&.external_customer_id || customer.external_id,
                    "name" => customer.name,
                    "address_line_1" => shipping[:address_line1],
                    "city" => shipping[:city],
                    "zip" => shipping[:zipcode],
                    "country" => shipping[:country],
                    "taxable" => customer.tax_identification_number.present?,
                    "tax_number" => customer.tax_identification_number
                  },
                  "fees" => charge_grouped_items.map { |items| cn_item(items) },
                  "tax_date" => credit_note.invoice.issuing_date
                }
              ]
            end

            def cn_item(items)
              fee = items.first.fee

              {
                "item_id" => cn_item_id(items),
                "item_code" => mapped_item(fee)&.external_id,
                "amount_cents" => items.sum(&:sub_total_excluding_taxes_amount_cents).round * -1
              }
            end

            private

            attr_reader :customer, :integration_customer, :credit_note
          end
        end
      end
    end
  end
end
