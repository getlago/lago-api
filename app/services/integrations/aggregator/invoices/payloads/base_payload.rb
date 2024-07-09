# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Payloads
        class BasePayload < Integrations::Aggregator::BasePayload
          def initialize(integration_customer:, invoice:, type: 'invoice')
            super(integration: integration_customer.integration)

            @invoice = invoice
            @integration_customer = integration_customer
            @type = type
          end

          def body
            [
              {
                'external_contact_id' => integration_customer.external_customer_id,
                'status' => 'AUTHORISED',
                'issuing_date' => invoice.issuing_date.to_time.utc.iso8601,
                'payment_due_date' => invoice.payment_due_date.to_time.utc.iso8601,
                'number' => invoice.number,
                'currency' => invoice.currency,
                'type' => 'ACCREC',
                'fees' => invoice.fees.order(created_at: :asc).map { |fee| item(fee) } + discounts
              }
            ]
          end

          private

          attr_reader :integration_customer, :invoice, :type

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
              'external_id' => mapped_item.external_id,
              'description' => fee.subscription? ? 'Subscription' : fee.invoice_name,
              'units' => fee.units,
              'precise_unit_amount' => fee.precise_unit_amount,
              'account_code' => mapped_item.external_account_code,
              'taxes_amount_cents' => amount(taxes_amount_cents(fee), resource: invoice),
              'precise_coupons_amount_cents' => fee.precise_coupons_amount_cents
            }
          end

          def taxes_amount_cents(fee)
            (fee.amount_cents - fee.precise_coupons_amount_cents) * fee.taxes_rate
          end

          def discounts
            output = []

            if credit_item && invoice.prepaid_credit_amount_cents > 0
              output << {
                'external_id' => credit_item.external_id,
                'description' => 'Prepaid credit',
                'units' => 1,
                'precise_unit_amount' => -amount(invoice.prepaid_credit_amount_cents, resource: invoice),
                'account_code' => credit_item.external_account_code
              }
            end

            if credit_note_item && invoice.credit_notes_amount_cents > 0
              output << {
                'external_id' => credit_note_item.external_id,
                'description' => 'Credit note',
                'units' => 1,
                'precise_unit_amount' => -amount(invoice.credit_notes_amount_cents, resource: invoice),
                'account_code' => credit_note_item.external_account_code
              }
            end

            output
          end
        end
      end
    end
  end
end
