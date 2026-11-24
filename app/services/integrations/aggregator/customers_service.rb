# frozen_string_literal: true

module Integrations
  module Aggregator
    class CustomersService < BaseRecordsService
      Result = BaseResult[:customers]

      LIMIT = 450
      MAX_REQUESTS = 25

      def call
        records = fetch_available_records
        return result if result.failure?

        ids = []

        ActiveRecord::Base.transaction do
          integration.integration_items.where(item_type: :customer).delete_all
          ids = insert_customers(records)
        end

        result.customers = IntegrationItem.where(id: ids).in_order_of(:id, ids)
        result
      end

      private

      def fetch_available_records
        records = []
        cursor = nil

        MAX_REQUESTS.times do
          response = fetch_records(limit: LIMIT, cursor:)
          records.concat(response["records"].reject { |record| unavailable_record?(record) })
          cursor = response["next_cursor"]

          return records if cursor.blank?
        end

        Rails.logger.warn(
          "QuickBooks customers over the fetch limit #{{integration_id: integration.id, fetched: records.size}.to_json}"
        )
        result.service_failure!(
          code: "integration_customers_limit_exceeded",
          message: "More than #{MAX_REQUESTS * LIMIT} customers to fetch"
        )
      end

      # Ids are unique per QuickBooks company, so the uniqueness validation adds nothing,
      # and a bulk insert keeps customer names out of the versions table.
      def insert_customers(records)
        rows = records.uniq { |record| record["id"] }.map do |record|
          {
            organization_id: integration.organization_id,
            integration_id: integration.id,
            external_id: record["id"],
            external_name: record["display_name"],
            item_type: IntegrationItem.item_types[:customer]
          }
        end
        return [] if rows.empty?

        IntegrationItem.insert_all!(rows, returning: %w[id]).rows.flatten # rubocop:disable Rails/SkipsModelValidations
      end

      def model
        "Customer"
      end
    end
  end
end
