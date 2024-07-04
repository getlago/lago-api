# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Payloads
        class Netsuite < BasePayload
          MAX_DECIMALS = 15

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

          private

          def item(fee)
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
              'quantity' => fee.units,
              'rate' => limited_rate(fee.precise_unit_amount)
            }
          end

          def discounts
            output = []

            if coupon_item && invoice.coupons_amount_cents > 0
              output << {
                'item' => coupon_item.external_id,
                'account' => coupon_item.external_account_code,
                'quantity' => 1,
                'rate' => -amount(invoice.coupons_amount_cents, resource: invoice)
              }
            end

            if credit_item && invoice.prepaid_credit_amount_cents > 0
              output << {
                'item' => credit_item.external_id,
                'account' => credit_item.external_account_code,
                'quantity' => 1,
                'rate' => -amount(invoice.prepaid_credit_amount_cents, resource: invoice)
              }
            end

            if credit_note_item && invoice.credit_notes_amount_cents > 0
              output << {
                'item' => credit_note_item.external_id,
                'account' => credit_note_item.external_account_code,
                'quantity' => 1,
                'rate' => -amount(invoice.credit_notes_amount_cents, resource: invoice)
              }
            end

            output
          end

          def limited_rate(precise_unit_amount)
            unit_amount_str = precise_unit_amount.to_s

            return precise_unit_amount if unit_amount_str.length <= MAX_DECIMALS

            decimal_position = unit_amount_str.index('.')

            return precise_unit_amount unless decimal_position

            precise_unit_amount.round(MAX_DECIMALS - 1 - decimal_position)
          end
        end
      end
    end
  end
end
