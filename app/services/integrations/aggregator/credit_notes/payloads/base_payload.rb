# frozen_string_literal: true

module Integrations
  module Aggregator
    module CreditNotes
      module Payloads
        class BasePayload < Integrations::Aggregator::BasePayload
          def initialize(integration_customer:, credit_note:)
            super(integration: integration_customer.integration)

            @credit_note = credit_note
            @integration_customer = integration_customer
          end

          def body
            [
              {
                'external_contact_id' => integration_customer.external_customer_id,
                'status' => 'AUTHORISED',
                'issuing_date' => credit_note.issuing_date.to_time.utc.iso8601,
                'number' => credit_note.number,
                'currency' => credit_note.currency,
                'type' => 'ACCRECCREDIT',
                'fees' => credit_note.items.map { |credit_note_item| item(credit_note_item) } + coupons
              }
            ]
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
              'external_id' => mapped_item.external_id,
              'description' => fee.subscription? ? 'Subscription' : fee.invoice_name,
              'units' => fee.units,
              'precise_unit_amount' => amount(credit_note_item.amount_cents, resource: credit_note_item.credit_note),
              'account_code' => mapped_item.external_account_code,
              'amount_cents' => credit_note_item.amount_cents,
              'taxes_amount_cents' => credit_note_item.credit_note.taxes_amount_cents
            }
          end

          def coupons
            output = []

            if credit_note.coupons_adjustment_amount_cents > 0
              output << {
                'external_id' => mapped_item.external_id,
                'description' => fee.invoice_name,
                'units' => 1,
                'precise_unit_amount' => fee.precise_unit_amount,
                'account_code' => mapped_item.external_account_code,
                'amount_cents' => credit_note.coupons_adjustment_amount_cents,
                'taxes_amount_cents' => 0
              }
            end

            output
          end
        end
      end
    end
  end
end
