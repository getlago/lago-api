# frozen_string_literal: true

module Integrations
  module Aggregator
    module WalletTransactions
      module Payloads
        class Factory
          def self.new_instance(integration_customer:, wallet_transaction:)
            case integration_customer&.integration&.type&.to_s
            when "Integrations::NetsuiteIntegration"
              Integrations::Aggregator::WalletTransactions::Payloads::Netsuite.new(integration_customer:, wallet_transaction:)
            else
              raise(NotImplementedError)
            end
          end
        end
      end
    end
  end
end
