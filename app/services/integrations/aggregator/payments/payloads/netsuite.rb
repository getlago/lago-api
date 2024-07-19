# frozen_string_literal: true

module Integrations
  module Aggregator
    module Payments
      module Payloads
        class Netsuite < BasePayload
          def body
            {
              'type' => 'customerpayment',
              'isDynamic' => true,
              'columns' => {
                'customer' => integration_customer.external_customer_id
              },
              'lines' => [
                {
                  'sublistId' => 'apply',
                  'lineItems' => [
                    {
                      # If the invoice is not synced yet, lets raise an error and retry. (doc: nil is an invalid request)
                      'doc' => integration_invoice&.external_id,
                      'apply' => true,
                      'amount' => amount(payment.amount_cents, resource: invoice)
                    }
                  ]
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
