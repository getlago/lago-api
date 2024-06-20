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
            raise(NotImplementedError)
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
              'item' => mapped_item.external_id,
              'account' => mapped_item.external_account_code,
              'quantity' => fee.units,
              'rate' => fee.precise_unit_amount
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
        end
      end
    end
  end
end
