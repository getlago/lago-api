# frozen_string_literal: true

module Integrations
  module Aggregator
    module CreditNotes
      module Payloads
        class BasePayload < Integrations::Aggregator::BasePayload
          def initialize(integration:, integration_customer:, credit_note:)
            super(integration:)

            @credit_note = credit_note
            @integration_customer = integration_customer
          end

          def body
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
                  'lineItems' => credit_note.items.map { |credit_note_item| item(credit_note_item) } + coupons
                }
              ],
              'options' => {
                'ignoreMandatoryFields' => false
              }
            }
          end

          private

          attr_reader :integration_customer, :credit_note

          def item(credit_note_item)
            fee = credit_note_item.fee

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

            return {} unless mapped_item

            {
              'item' => mapped_item.external_id,
              'account' => mapped_item.external_account_code,
              'quantity' => 1,
              'rate' => amount(credit_note_item.amount_cents, resource: credit_note_item.credit_note)
            }
          end

          def coupons
            output = []

            if credit_note.coupons_adjustment_amount_cents > 0
              output << {
                'item' => coupon_item&.external_id,
                'account' => coupon_item&.external_account_code,
                'quantity' => 1,
                'rate' => -amount(credit_note.coupons_adjustment_amount_cents, resource: credit_note)
              }
            end

            output
          end
        end
      end
    end
  end
end
