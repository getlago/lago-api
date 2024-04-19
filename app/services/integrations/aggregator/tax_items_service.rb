# frozen_string_literal: true

module Integrations
  module Aggregator
    class TaxItemsService < BaseService
      LIMIT = 300
      MAX_SUBSEQUENT_REQUESTS = 10

      def action_path
        "v1/#{provider}/taxitems"
      end

      def call
        @cursor = ''
        @items = []

        ActiveRecord::Base.transaction do
          MAX_SUBSEQUENT_REQUESTS.times do |_i|
            response = http_client.get(headers:, params:)

            handle_tax_items(response['records'])
            @cursor = response['next_cursor']

            break if cursor.blank?
          end
        end
        result.tax_items = items

        result
      end

      private

      attr_reader :cursor, :items

      def headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}",
          'Provider-Config-Key' => provider,
        }
      end

      def handle_tax_items(new_items)
        @items = items.concat(new_items)

        new_items.each do |item|
          integration_item = IntegrationItem.new(
            integration:,
            external_id: item['id'],
            name: item['name'],
            item_type: :tax,
          )

          integration_item.save!
        end
      end

      def params
        {
          limit: LIMIT,
          cursor:,
        }
      end
    end
  end
end
