# frozen_string_literal: true

module Integrations
  module Aggregator
    class CustomersService < BaseRecordsService
      Result = BaseResult[:customers]

      LIMIT = 450
      MAX_SUBSEQUENT_REQUESTS = 15

      def call
        @cursor = nil
        @items = []

        ActiveRecord::Base.transaction do
          integration.integration_items.where(item_type: :customer).destroy_all

          MAX_SUBSEQUENT_REQUESTS.times do
            response = fetch_records(limit: LIMIT, cursor:)

            handle_customers(response["records"].reject { |customer| unavailable_record?(customer) })
            @cursor = response["next_cursor"]

            break if cursor.blank?
          end
        end
        result.customers = items

        result
      end

      private

      attr_reader :cursor, :items

      def handle_customers(new_items)
        new_items.each do |item|
          integration_item = IntegrationItem.new(
            organization_id: integration.organization_id,
            integration:,
            external_id: item["id"],
            external_name: item["display_name"],
            item_type: :customer
          )

          integration_item.save!

          @items << integration_item
        end
      end

      def model
        "Customer"
      end
    end
  end
end
