# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      # NOTE: Reads the SyncToken of a QuickBooks customer through the Nango proxy, as QuickBooks refuses an
      #       update without the current one. Proxy errors carry the realm id in their URI, so none of them
      #       leaves this service: they become a failure with a fixed code and message.
      class FetchQuickbooksSyncTokenService < Integrations::Aggregator::BaseService
        Result = BaseResult[:sync_token, :display_name]

        LOOKUP_FAILURE_LOG = "QuickBooks customer lookup failed"

        def initialize(integration:, integration_customer:)
          @integration_customer = integration_customer

          super(integration:)
        end

        def action_path
          "proxy/v3/company/#{ERB::Util.url_encode(integration.realm_id)}/customer/" \
            "#{ERB::Util.url_encode(integration_customer.external_customer_id)}"
        end

        def call
          if integration.realm_id.blank?
            return result.service_failure!(code: "realm_id_missing", message: "QuickBooks connection has no company id")
          end

          throttle!(:quickbooks)

          response = http_client.get(headers:)
          sync_token = response.dig("Customer", "SyncToken") if response.is_a?(Hash)

          if sync_token.blank?
            result.service_failure!(code: "sync_token_missing", message: "QuickBooks customer has no SyncToken")
          else
            result.sync_token = sync_token.to_s
            result.display_name = response.dig("Customer", "DisplayName")
            result
          end
        rescue LagoHttpClient::HttpError => e
          log_nango_failure(LOOKUP_FAILURE_LOG, e, status: e.error_code)
          raise throttling_error(:quickbooks) if quickbooks_rate_limited?(e)
          return customer_not_found if e.error_code.to_i == 404

          lookup_failed
        rescue *LOOKUP_ERRORS => e
          log_nango_failure(LOOKUP_FAILURE_LOG, e)
          lookup_failed
        end

        private

        attr_reader :integration_customer

        # The customer was deleted or merged in QuickBooks: the merchant has to link another one.
        def customer_not_found
          result.service_failure!(code: "customer_not_found", message: "QuickBooks customer not found")
        end

        def lookup_failed
          result.service_failure!(code: "customer_lookup_failed", message: "QuickBooks customer lookup failed")
        end
      end
    end
  end
end
