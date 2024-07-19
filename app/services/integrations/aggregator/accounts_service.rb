# frozen_string_literal: true

module Integrations
  module Aggregator
    class AccountsService < BaseService
      LIMIT = 450
      MAX_SUBSEQUENT_REQUESTS = 15

      def action_path
        "v1/#{provider}/accounts"
      end

      def call
        @cursor = ''
        @items = []

        ActiveRecord::Base.transaction do
          integration.integration_items.where(item_type: :account).destroy_all

          MAX_SUBSEQUENT_REQUESTS.times do |_i|
            response = http_client.get(headers:, params:)

            handle_accounts(response['records'])
            @cursor = response['next_cursor']

            break if cursor.blank?
          end
        end
        result.accounts = items

        result
      end

      private

      attr_reader :cursor, :items

      def headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}",
          'Provider-Config-Key' => provider_key
        }
      end

      def handle_accounts(new_items)
        new_items.each do |item|
          integration_item = IntegrationItem.new(
            integration:,
            external_id: item['id'],
            external_account_code: item['code'],
            external_name: item['name'],
            item_type: :account
          )

          integration_item.save!

          @items << integration_item
        end
      end

      def params
        {
          limit: LIMIT,
          cursor:
        }
      end
    end
  end
end
