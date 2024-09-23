# frozen_string_literal: true

module Integrations
  module Aggregator
    module CreditNotes
      module Payloads
        class Netsuite < BasePayload
          def body
            {
              'type' => 'creditmemo',
              'isDynamic' => true,
              'columns' => columns,
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

          def columns
            result = {
              'tranid' => credit_note.number,
              'entity' => integration_customer.external_customer_id,
              'taxregoverride' => true,
              'taxdetailsoverride' => true,
              'otherrefnum' => credit_note.number,
              'custbody_ava_disable_tax_calculation' => true,
              'custbody_lago_id' => credit_note.id,
              'tranId' => credit_note.id
            }

            if tax_item&.tax_nexus.present?
              result['nexus'] = tax_item.tax_nexus
            end

            result
          end

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

            unless mapped_item
              raise Integrations::Aggregator::BasePayload::Failure.new(nil, code: 'invalid_mapping')
            end

            {
              'item' => mapped_item.external_id,
              'account' => mapped_item.external_account_code,
              'quantity' => 1,
              'rate' => amount(credit_note_item.amount_cents, resource: credit_note_item.credit_note),
              'taxdetailsreference' => credit_note_item.id
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
