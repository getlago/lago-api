# frozen_string_literal: true

module Integrations
  module Aggregator
    class AccountsService < BaseService
      def action_path
        "v1/#{provider}/accounts"
      end

      def call
        response = http_client.get(headers:)

        result.accounts = handle_accounts(response['records'])

        result
      end

      private

      def headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}",
          'Provider-Config-Key' => provider
        }
      end

      def handle_accounts(accounts)
        accounts.map do |account|
          OpenStruct.new(
            external_id: account['id'],
            external_account_code: account['code'],
            external_name: account['name']
          )
        end
      end
    end
  end
end
