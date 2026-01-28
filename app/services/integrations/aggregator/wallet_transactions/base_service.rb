# frozen_string_literal: true

module Integrations
  module Aggregator
    module WalletTransactions
      class BaseService < Integrations::Aggregator::BaseService
        def initialize(wallet_transaction:)
          @wallet_transaction = wallet_transaction

          super(integration:)
        end

        private

        attr_reader :wallet_transaction

        delegate :customer, to: :wallet_transaction, allow_nil: true

        def headers
          {
            "Connection-Id" => integration.connection_id,
            "Authorization" => "Bearer #{secret_key}",
            "Provider-Config-Key" => provider_key
          }
        end

        def integration
          return nil unless integration_customer

          integration_customer&.integration
        end

        def integration_customer
          @integration_customer ||= customer&.integration_customers&.accounting_kind&.first
        end

        def payload
          Integrations::Aggregator::WalletTransactions::Payloads::Factory.new_instance(
            integration_customer:,
            wallet_transaction:
          )
        end
      end
    end
  end
end
