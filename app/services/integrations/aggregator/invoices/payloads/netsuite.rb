# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Payloads
        class Netsuite < BasePayload
          def body
            {
              'type' => type,
              'isDynamic' => true,
              'columns' => {
                'tranid' => invoice.id,
                'entity' => integration_customer.external_customer_id,
                'istaxable' => true,
                'taxitem' => tax_item&.external_id,
                'taxamountoverride' => amount(invoice.taxes_amount_cents, resource: invoice),
                'otherrefnum' => invoice.number,
                'custbody_lago_id' => invoice.id,
                'custbody_ava_disable_tax_calculation' => true
              },
              'lines' => [
                {
                  'sublistId' => 'item',
                  'lineItems' => invoice.fees.order(created_at: :asc).map { |fee| item(fee) } + discounts
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
end
