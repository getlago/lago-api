# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module CreditNotes
        module Payloads
          class Avalara < BasePayload
            def initialize(integration:, customer:, integration_customer:, credit_note:)
              super(integration:, billing_entity: customer.billing_entity)

              @customer = customer
              @integration_customer = integration_customer
              @credit_note = credit_note
              @billing_entity = customer.billing_entity
            end

            def body
              shipping = customer.effective_shipping_address

              [
                {
                  "id" => "cn_#{credit_note.id}",
                  "type" => "returnInvoice",
                  "issuing_date" => credit_note.issuing_date,
                  "currency" => credit_note.currency,
                  "contact" => {
                    "external_id" => integration_customer&.external_customer_id,
                    "name" => customer.name,
                    "address_line_1" => shipping[:address_line1],
                    "city" => shipping[:city],
                    "zip" => shipping[:zipcode],
                    "region" => shipping[:state],
                    "country" => shipping[:country],
                    "taxable" => customer.tax_identification_number.present?,
                    "tax_number" => customer.tax_identification_number
                  },
                  "billing_entity" => {
                    "address_line_1" => billing_entity&.address_line1,
                    "city" => billing_entity&.city,
                    "zip" => billing_entity&.zipcode,
                    "region" => billing_entity&.state,
                    "country" => billing_entity&.country
                  },
                  "fees" => charge_grouped_items.map { |items| cn_item(items) }
                }
              ]
            end

            def cn_item(items)
              fee = items.first.fee

              {
                "item_id" => cn_item_id(items),
                "item_code" => mapped_item(fee)&.external_id,
                "unit" => items.map(&:fee).uniq.sum(&:units),
                "amount" => item_amount(items, fee)
              }
            end

            private

            attr_reader :customer, :integration_customer, :credit_note, :billing_entity

            def item_amount(items, fee)
              amount_cents = items.sum(&:sub_total_excluding_taxes_amount_cents).round * -1
              amount = amount_cents.fdiv(fee.amount.currency.subunit_to_unit)

              amount.to_s
            end
          end
        end
      end
    end
  end
end
