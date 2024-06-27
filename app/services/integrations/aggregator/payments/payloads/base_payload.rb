# frozen_string_literal: true

module Integrations
  module Aggregator
    module Payments
      module Payloads
        class BasePayload < Integrations::Aggregator::BasePayload
          def initialize(integration:, payment:)
            super(integration:)

            @payment = payment
          end

          def body
            [
              {
                'invoice_id' => integration_invoice&.external_id,
                'account_code' => account_item&.external_account_code,
                'date' => payment.created_at.utc.iso8601,
                'amount_cents' => payment.amount_cents
              }
            ]
          end

          private

          attr_reader :payment

          delegate :invoice, to: :payment, allow_nil: true

          def integration_invoice
            invoice.integration_resources.where(resource_type: 'invoice', syncable_type: 'Invoice').first
          end

          def integration_customer
            @integration_customer ||= invoice.customer&.integration_customers&.first
          end
        end
      end
    end
  end
end
