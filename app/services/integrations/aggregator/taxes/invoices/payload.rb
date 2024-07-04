# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class Payload < BasePayload
          def initialize(integration:, customer:, invoice:, fees: [])
            super(integration:)

            @customer = customer
            @invoice = invoice
            @fees = fees
          end

          def body
            [
              {
                'issuing_date' => invoice.issuing_date,
                'currency' => invoice.currency,
                'contact' => {
                  'external_id' => customer.external_id,
                  'name' => customer.name,
                  'address_line_1' => customer.shipping_address_line1,
                  'city' => customer.shipping_city,
                  'zip' => customer.shipping_zipcode,
                  'country' => customer.shipping_country,
                  'taxable' => customer.tax_identification_number.present?,
                  'tax_number' => customer.tax_identification_number
                },
                'fees' => fees.order(created_at: :asc).map { |fee| fee_item(fee) }
              }
            ]
          end

          def fee_item(fee)
            # TODO: Update later with other fee types
            mapped_item = add_on_item(fee)

            {
              'item_id' => fee.item_id,
              'item_code' => mapped_item.external_id,
              'amount_cents' => fee.amount_cents
            }
          end

          private

          attr_reader :customer, :invoice, :fees
        end
      end
    end
  end
end
