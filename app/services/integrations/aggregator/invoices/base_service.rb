# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class BaseService < Integrations::Aggregator::BaseService
        def initialize(invoice:)
          @invoice = invoice

          super(integration:)
        end

        private

        attr_reader :invoice

        delegate :customer, to: :invoice, allow_nil: true

        def headers
          {
            'Connection-Id' => integration.connection_id,
            'Authorization' => "Bearer #{secret_key}",
            'Provider-Config-Key' => provider
          }
        end

        def integration
          return nil unless integration_customer

          integration_customer&.integration
        end

        def integration_customer
          @integration_customer ||= customer&.integration_customers&.first
        end

        def billable_metric_item(fee)
          integration
            .integration_mappings
            .find_by(mappable_type: 'BillableMetric', mappable_id: fee.billable_metric.id) || fallback_item
        end

        def add_on_item(fee)
          integration
            .integration_mappings
            .find_by(mappable_type: 'AddOn', mappable_id: fee.add_on.id) || fallback_item
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
              'rate' => -amount(invoice.coupons_amount_cents)
            }
          end

          if credit_item && invoice.prepaid_credit_amount_cents > 0
            output << {
              'item' => credit_item.external_id,
              'account' => credit_item.external_account_code,
              'quantity' => 1,
              'rate' => -amount(invoice.prepaid_credit_amount_cents)
            }
          end

          if credit_note_item && invoice.credit_notes_amount_cents > 0
            output << {
              'item' => credit_note_item.external_id,
              'account' => credit_note_item.external_account_code,
              'quantity' => 1,
              'rate' => -amount(invoice.credit_notes_amount_cents)
            }
          end

          output
        end

        def payload(type)
          {
            'type' => type,
            'isDynamic' => true,
            'columns' => {
              'tranid' => invoice.id,
              'entity' => integration_customer.external_customer_id,
              'istaxable' => true,
              'taxitem' => tax_item&.external_id,
              'taxamountoverride' => amount(invoice.taxes_amount_cents),
              'otherrefnum' => invoice.number,
              'custbody_lago_id' => invoice.id,
              'custbody_ava_disable_tax_calculation' => true
            },
            'lines' => [
              {
                'sublistId' => 'item',
                'lineItems' => invoice.fees.map { |fee| item(fee) } + discounts
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
