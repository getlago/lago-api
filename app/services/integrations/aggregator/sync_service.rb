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
          syncs: sync_list,
        }

        response = http_client.post_with_response(payload, headers)
        result.response = response

        result
      end

      private

      # NOTE: Extend it with other providers if needed
      def sync_list
        list = case integration.type
               when 'Integrations::NetsuiteIntegration'
                 {
                   accounts: 'netsuite-accounts-sync',
                   items: 'netsuite-items-sync',
                   subsidiaries: 'netsuite-subsidiaries-sync',
                   contacts: 'netsuite-contacts-sync',
                   tax_items: 'netsuite-tax-items-sync',
                 }
        end

        return [list[:items]] if options[:only_items]
        return [list[:tax_items]] if options[:only_tax_items]

        list.values
      end
    end
  end
end
