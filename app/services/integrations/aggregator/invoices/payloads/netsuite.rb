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
              'columns' => columns,
              'lines' => [
                {
                  'sublistId' => 'item',
                  'lineItems' => invoice.fees.where('amount_cents > ?', 0).order(created_at: :asc).map do |fee|
                    item(fee)
                  end + discounts
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
              'tranid' => invoice.id,
              'entity' => integration_customer.external_customer_id,
              'istaxable' => true,
              'otherrefnum' => invoice.number,
              'custbody_lago_id' => invoice.id,
              'custbody_ava_disable_tax_calculation' => true,
              'custbody_lago_invoice_link' => invoice_url,
              'duedate' => due_date
            }

            if tax_item
              result['taxitem'] = tax_item.external_id
              result['taxamountoverride'] = amount(invoice.taxes_amount_cents, resource: invoice)
            end

            result
          end

          def invoice_url
            url = ENV["LAGO_FRONT_URL"].presence || "https://app.getlago.com"

            URI.join(url, "/customer/#{invoice.customer.id}/", "invoice/#{invoice.id}/overview").to_s
          end

          def due_date
            invoice.payment_due_date&.strftime("%-m/%-d/%Y")
          end

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
