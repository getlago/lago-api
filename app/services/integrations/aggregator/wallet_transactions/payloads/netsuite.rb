# frozen_string_literal: true

module Integrations
  module Aggregator
    module WalletTransactions
      module Payloads
        class Netsuite < BasePayload
          def body
            {
              "type" => "walletTransaction",
              "columns" => columns
            }
          end

          private

          def columns
            result = {
              "amount" => wallet_transaction.amount,
              "credit_amount" => wallet_transaction.credit_amount,
              "metadata" => wallet_transaction.metadata,
              "name" => wallet_transaction.name,
              "wallet_id" => wallet_transaction.wallet_id,
              "priority" => wallet_transaction.priority,
              "settled_at" => wallet_transaction.settled_at&.strftime("%-m/%-d/%Y %H:%M:%S"),
              "source" => wallet_transaction.source,
              "transaction_status" => wallet_transaction.transaction_status
            }

            mapped_currency = netsuite_currency_for(currency: wallet_transaction.wallet.currency)
            if mapped_currency.present?
              result["currency"] = mapped_currency.to_s
            end

            result
          end

          def netsuite_currency_for(currency:)
            mapping = IntegrationCollectionMappings::NetsuiteCollectionMapping.find_by(
              integration_id: integration_customer.integration_id,
              mapping_type: :currencies
            )
            mapping&.currencies&.dig(currency)
          end
        end
      end
    end
  end
end
