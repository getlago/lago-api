# frozen_string_literal: true

module Integrations
  module Aggregator
    module WalletTransactions
      module Payloads
        class BasePayload < Integrations::Aggregator::BasePayload
          def initialize(integration_customer:, wallet_transactiom:)
            super(integration: integration_customer.integration, billing_entity: integration_customer.customer.billing_entity)

            @wallet_transactiom = wallet_transactiom
            @integration_customer = integration_customer
          end

          def body
            [
              {
                "external_contact_id" => integration_customer.external_customer_id,
                "status" => "AUTHORISED",
                "issuing_date" => @wallet_transaction.created_at.to_time.utc.iso8601,
                "number" => invoice.number,
              }
            ]
          end

          def integration_invoice
            @integration_invoice ||=
              IntegrationResource.find_by(integration:, syncable: invoice, resource_type: "invoice")
          end

          private

          attr_reader :integration_customer, :invoice
          attr_accessor :remaining_taxes_amount_cents
        end
      end
    end
  end
end
