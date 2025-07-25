# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Payloads
        class Netsuite < BasePayload
          MAX_DECIMALS = 15

          def body
            result = {
              "type" => "invoice",
              "isDynamic" => true,
              "columns" => columns,
              "lines" => [
                {
                  "sublistId" => "item",
                  "lineItems" => fee_items + discounts
                }
              ],
              "options" => {
                "ignoreMandatoryFields" => false
              }
            }

            if tax_item_complete?
              result["taxdetails"] = [
                {
                  "sublistId" => "taxdetails",
                  "lineItems" => tax_line_items + discount_taxes
                }
              ]
            end

            result
          end

          private

          def columns
            result = {
              "tranid" => invoice.number,
              "custbody_ava_disable_tax_calculation" => true,
              "custbody_lago_invoice_link" => invoice_url
            }

            unless tax_item_complete?
              result["trandate"] = issuing_date
            end

            result = result.merge(
              {
                "duedate" => due_date,
                "taxdetailsoverride" => true,
                "custbody_lago_id" => invoice.id,
                "entity" => integration_customer.external_customer_id,
                "lago_plan_codes" => invoice.invoice_subscriptions.map(&:subscription).map(&:plan).map(&:code).join(",")
              }
            )

            if tax_item&.tax_nexus.present?
              result["nexus"] = tax_item.tax_nexus
            end

            result["taxregoverride"] = true

            result
          end

          def tax_line_items
            fees.map { |fee| tax_line_item(fee) }
          end

          def tax_line_item(fee)
            {
              "taxdetailsreference" => fee.id,
              "taxamount" => amount(fee.taxes_amount_cents, resource: invoice),
              "taxbasis" => 1,
              "taxrate" => fee.taxes_rate,
              "taxtype" => tax_item.tax_type,
              "taxcode" => tax_item.tax_code
            }
          end

          def invoice_url
            url = ENV["LAGO_FRONT_URL"].presence || "https://app.getlago.com"

            URI.join(url, "/customer/#{invoice.customer.id}/", "invoice/#{invoice.id}/overview").to_s
          end

          def due_date
            invoice.payment_due_date&.strftime("%-m/%-d/%Y")
          end

          def issuing_date
            invoice.issuing_date&.strftime("%-m/%-d/%Y")
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

            unless mapped_item
              raise Integrations::Aggregator::BasePayload::Failure.new(nil, code: "invalid_mapping")
            end

            from_property = fee.charge? ? "charges_from_datetime" : "from_datetime"
            to_property = fee.charge? ? "charges_to_datetime" : "to_datetime"

            {
              "item" => mapped_item.external_id,
              "account" => mapped_item.external_account_code,
              "quantity" => limited_rate(fee.units),
              "rate" => limited_rate(fee.precise_unit_amount),
              "amount" => limited_rate(amount(fee.amount_cents, resource: invoice)),
              "taxdetailsreference" => fee.id,
              "custcol_service_period_date_from" => fee.properties[from_property]&.to_date&.strftime("%-m/%-d/%Y"),
              "custcol_service_period_date_to" => fee.properties[to_property]&.to_date&.strftime("%-m/%-d/%Y"),
              "description" => fee.item_name
            }
          end

          def discounts
            output = []

            if coupon_item && invoice.coupons_amount_cents > 0
              output << {
                "item" => coupon_item.external_id,
                "account" => coupon_item.external_account_code,
                "quantity" => 1,
                "rate" => -amount(invoice.coupons_amount_cents, resource: invoice),
                "taxdetailsreference" => "coupon_item",
                "description" => invoice.credits.coupon_kind.map(&:item_name).join(",")
              }
            end

            if credit_item && invoice.prepaid_credit_amount_cents > 0
              output << {
                "item" => credit_item.external_id,
                "account" => credit_item.external_account_code,
                "quantity" => 1,
                "rate" => -amount(invoice.prepaid_credit_amount_cents, resource: invoice),
                "taxdetailsreference" => "credit_item",
                "description" => "Prepaid credits"
              }
            end

            if credit_item && invoice.progressive_billing_credit_amount_cents > 0
              output << {
                "item" => credit_item.external_id,
                "account" => credit_item.external_account_code,
                "quantity" => 1,
                "rate" => -amount(invoice.progressive_billing_credit_amount_cents, resource: invoice),
                "taxdetailsreference" => "credit_item_progressive_billing",
                "description" => invoice.credits.progressive_billing_invoice_kind.map(&:item_name).join(",")
              }
            end

            if credit_note_item && invoice.credit_notes_amount_cents > 0
              output << {
                "item" => credit_note_item.external_id,
                "account" => credit_note_item.external_account_code,
                "quantity" => 1,
                "rate" => -amount(invoice.credit_notes_amount_cents, resource: invoice),
                "taxdetailsreference" => "credit_note_item",
                "description" => invoice.credits.credit_note_kind.map(&:item_name).join(",")
              }
            end

            output
          end

          def discount_taxes
            output = []

            if invoice.coupons_amount_cents > 0
              tax_diff_amount_cents = invoice.taxes_amount_cents - fees.sum { |f| f["taxes_amount_cents"] }

              output << {
                "taxbasis" => 1,
                "taxamount" => amount(tax_diff_amount_cents, resource: invoice),
                "taxrate" => invoice.taxes_rate,
                "taxtype" => tax_item.tax_type,
                "taxcode" => tax_item.tax_code,
                "taxdetailsreference" => "coupon_item"
              }
            end

            if credit_item && invoice.prepaid_credit_amount_cents > 0
              output << {
                "taxbasis" => 1,
                "taxamount" => 0,
                "taxrate" => invoice.taxes_rate,
                "taxtype" => tax_item.tax_type,
                "taxcode" => tax_item.tax_code,
                "taxdetailsreference" => "credit_item"
              }
            end

            if credit_item && invoice.progressive_billing_credit_amount_cents > 0
              output << {
                "taxbasis" => 1,
                "taxamount" => 0,
                "taxrate" => invoice.taxes_rate,
                "taxtype" => tax_item.tax_type,
                "taxcode" => tax_item.tax_code,
                "taxdetailsreference" => "credit_item_progressive_billing"
              }
            end

            if credit_note_item && invoice.credit_notes_amount_cents > 0
              output << {
                "taxbasis" => 1,
                "taxamount" => 0,
                "taxrate" => invoice.taxes_rate,
                "taxtype" => tax_item.tax_type,
                "taxcode" => tax_item.tax_code,
                "taxdetailsreference" => "credit_note_item"
              }
            end

            output
          end

          def limited_rate(precise_unit_amount)
            unit_amount_str = precise_unit_amount.to_s

            return precise_unit_amount if unit_amount_str.length <= MAX_DECIMALS

            decimal_position = unit_amount_str.index(".")

            return precise_unit_amount unless decimal_position

            precise_unit_amount.round(MAX_DECIMALS - 1 - decimal_position)
          end
        end
      end
    end
  end
end
