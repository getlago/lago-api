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
            @remaining_coupons_amount_cents = credit_note.coupons_adjustment_amount_cents
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
                'fees' => credit_note_items_with_adjusted_taxes(credit_note_items)
              }
            ]
          end

          private

          attr_reader :integration_customer, :credit_note, :remaining_coupons_amount_cents

          def credit_note_items
            @credit_note_items ||= credit_note.items.map { |credit_note_item| item(credit_note_item) }
          end

          def credit_note_items_with_adjusted_taxes(credit_note_items)
            taxes_amount_cents_sum = credit_note_items.sum { |f| f['taxes_amount_cents'] }

            return credit_note_items if taxes_amount_cents_sum == credit_note.taxes_amount_cents

            adjusted_first_tax = false

            credit_note_items.map do |credit_note_item|
              if credit_note_item['taxes_amount_cents'] > 0 && !adjusted_first_tax
                credit_note_item['taxes_amount_cents'] += credit_note.taxes_amount_cents - taxes_amount_cents_sum
                adjusted_first_tax = true
              end

              credit_note_item
            end
          end

          def coupons_amount_cents(item)
            return 0 if remaining_coupons_amount_cents <= 0

            if remaining_coupons_amount_cents > item.amount_cents
              coupons_amount_cents = item.amount_cents

              @remaining_coupons_amount_cents = remaining_coupons_amount_cents - item.amount_cents
            else
              coupons_amount_cents = remaining_coupons_amount_cents
              @remaining_coupons_amount_cents = 0
            end

            coupons_amount_cents
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

            return {} unless mapped_item

            precise_unit_amount = credit_note_item.amount_cents - coupons_amount_cents(credit_note_item)

            {
              'external_id' => mapped_item.external_id,
              'description' => fee.subscription? ? 'Subscription' : fee.invoice_name,
              'units' => (precise_unit_amount > 0) ? 1 : 0,
              'precise_unit_amount' => amount(credit_note_item.amount_cents - coupons_amount_cents(credit_note_item), resource: credit_note_item.credit_note),
              # 'amount_cents' => credit_note_item.amount_cents - coupons_amount_cents(credit_note_item)
              'account_code' => mapped_item.external_account_code,
              'taxes_amount_cents' => amount(taxes_amount_cents(credit_note_item), resource: credit_note_item.credit_note)
            }
          end

          def taxes_amount_cents(credit_note_item)
            (credit_note_item.amount_cents - credit_note_item.precise_coupons_amount_cents) *
              credit_note_item.credit_note.taxes_rate
          end
        end
      end
    end
  end
end
