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

      def fetch_records(limit: nil, cursor: nil)
        params = {model:, limit:, cursor:}.compact_blank

        http_client.get(headers:, params:)
      end
    end
  end
end
