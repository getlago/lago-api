# frozen_string_literal: true

module Integrations
  module Aggregator
    # NOTE: Reads records stored by a Nango sync through GET /records
    class BaseRecordsService < BaseService
      def action_path
        "records"
      end

      private

      def model
        raise NotImplementedError
      end

      # QuickBooks deactivates items, accounts and customers instead of deleting them, so they must not reach the pickers.
      def unavailable_record?(record)
        return false unless integration.is_a?(Integrations::QuickbooksIntegration)

        record["active"] == false || record.dig("_nango_metadata", "deleted_at").present?
      end

      def fetch_records(limit: nil, cursor: nil)
        params = {model:, limit:, cursor:}.compact_blank

        http_client.get(headers:, params:)
      end
    end
  end
end
