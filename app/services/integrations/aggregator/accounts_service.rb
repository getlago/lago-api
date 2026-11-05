# frozen_string_literal: true

module Integrations
  module Aggregator
    class AccountsService < BaseRecordsService
      Result = BaseResult[:accounts]

      LIMIT = 450
      MAX_SUBSEQUENT_REQUESTS = 15

      def call
        @cursor = nil
        @items = []

        ActiveRecord::Base.transaction do
          integration.integration_items.where(item_type: :account).destroy_all

          MAX_SUBSEQUENT_REQUESTS.times do |_i|
            response = fetch_records(limit: LIMIT, cursor:)

            handle_accounts(response["records"])
            @cursor = response["next_cursor"]

            break if cursor.blank?
          end
        end
        result.accounts = items

        result
      end

      private

      attr_reader :cursor, :items

      def handle_accounts(new_items)
        new_items.each do |item|
          integration_item = IntegrationItem.new(
            organization_id: integration.organization_id,
            integration:,
            external_id: item["id"],
            external_account_code: item["code"],
            external_name: item["name"],
            item_type: :account
          )

          integration_item.save!

          @items << integration_item
        end
      end

      def model
        "Account"
      end
    end
  end
end
