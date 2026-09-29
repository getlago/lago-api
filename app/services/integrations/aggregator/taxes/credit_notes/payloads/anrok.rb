# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module CreditNotes
        module Payloads
          class Anrok < Integrations::Aggregator::Taxes::BasePayload
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

            # NOTE: A charge split by charge filters or by grouped_by is credited through one item
            #       per fee, so a single charge could take dozens of the 1200 line items Anrok
            #       accepts. Anrok rounds tax once per transaction, so merging them is safe.
            def charge_grouped_items
              ChargeGroup.by_charge(credit_note.items.order(created_at: :asc, id: :asc)) do |item|
                item.fee.charge_id if item.fee.charge?
              end
            end

            # NOTE: Fee#item_id is the billable metric for a charge fee, so two charges over the
            #       same metric would share one identifier within a payload.
            #       Singleton credits also use charge_id, including partial credits of a
            #       grouped charge. This intentionally changes their previous metric ID.
            def cn_item_id(items)
              fee = items.first.fee

              fee.charge? ? fee.charge_id : fee.item_id
            end
          end
        end
      end
    end
  end
end
