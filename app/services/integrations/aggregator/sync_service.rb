# frozen_string_literal: true

module Integrations
  module Aggregator
    class SyncService < BaseService
      def action_path
        'sync/start'
      end

      def call
        payload = {
          provider_config_key: provider,
          syncs: sync_items,
        }

        response = http_client.post_with_response(payload, headers)
        result.response = response

        result
      end

      private

      # NOTE: Extend it with other providers if needed
      def sync_items
        case integration.type
        when 'Integrations::NetsuiteIntegration'
          %w[
            netsuite-accounts-sync
            netsuite-items-sync
            netsuite-subsidiaries-sync
            netsuite-contacts-sync
            netsuite-tax-items-sync
          ]
        end
      end
    end
  end
end
