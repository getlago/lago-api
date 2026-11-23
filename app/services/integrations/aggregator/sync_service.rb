# frozen_string_literal: true

module Integrations
  module Aggregator
    class SyncService < BaseService
      Result = BaseResult[:response]

      def action_path
        "sync/trigger"
      end

      def call
        payload = {
          provider_config_key: provider_key,
          syncs: sync_list
        }

        response = http_client.post_with_response(payload, headers)
        result.response = response

        result
      end

      private

      # NOTE: Extend it with other providers if needed
      def sync_list
        list = case integration.type
        when "Integrations::NetsuiteIntegration"
          {
            subsidiaries: "netsuite-subsidiaries-sync"
          }
        when "Integrations::XeroIntegration"
          {
            accounts: "xero-accounts-sync",
            items: "xero-items-sync",
            contacts: "xero-contacts-sync"
          }
        when "Integrations::QuickbooksIntegration"
          {
            accounts: "accounts",
            items: "items",
            contacts: "customers"
          }
        end

        if options[:only_items]
          [list[:items]]
        elsif options[:only_accounts]
          [list[:accounts]]
        elsif options[:only_customers]
          [list[:contacts]]
        else
          list.values
        end
      end
    end
  end
end
