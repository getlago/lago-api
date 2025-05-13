# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module CreditNotes
        module Payloads
          class Avalara < BasePayload
            def initialize(integration:, customer:, integration_customer:, credit_note:)
              super(integration:)

              @customer = customer
              @integration_customer = integration_customer
              @credit_note = credit_note
              @billing_entity = customer.billing_entity
            end

            def body
              [
                {
                  "id" => "cn_#{credit_note.id}",
                  "type" => "returnInvoice",
                  "issuing_date" => credit_note.issuing_date,
                  "currency" => credit_note.currency,
                  "contact" => {
                    "external_id" => integration_customer&.external_customer_id,
                    "name" => customer.name,
                    "address_line_1" => customer.shipping_address_line1 || customer.address_line1,
                    "city" => customer.shipping_city || customer.city,
                    "zip" => customer.shipping_zipcode || customer.zipcode,
                    "region" => customer.shipping_state || customer.state,
                    "country" => customer.shipping_country || customer.country,
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
                  "fees" => credit_note.items.order(created_at: :asc).map { |item| cn_item(item) }
                }
              ]
            end

            def cn_item(item)
              fee = item.fee

              mapped_item = if fee.charge?
                billable_metric_item(fee)
              elsif fee.add_on_id.present?
                add_on_item(fee)
              elsif fee.commitment?
                commitment_item
              elsif fee.subscription?
                subscription_item
              end
              mapped_item ||= OpenStruct.new

              {
                "item_id" => fee.item_id,
                "item_code" => mapped_item.external_id,
                "unit" => fee.units,
                "amount" => item_amount(item, fee)
              }
            end

            private

            attr_reader :customer, :integration_customer, :credit_note, :billing_entity

            def item_amount(item, fee)
              amount = (item.sub_total_excluding_taxes_amount_cents.to_i * -1).fdiv(fee.amount.currency.subunit_to_unit)

              amount.to_s
            end
          end
        end
      end
    end
  end
end
