# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      # NOTE: Finds the QuickBooks customer holding a DisplayName and returns its id when its Notes hold the
      #       given marker, which means Lago created it in an earlier attempt that did not store the id.
      #       Proxy errors carry the realm id in their URI, so none of them leaves this service: they become
      #       a failure with a fixed code and message.
      class FindQuickbooksCustomerService < Integrations::Aggregator::BaseService
        Result = BaseResult[:contact_id]

        LOOKUP_FAILURE_LOG = "QuickBooks customer search failed"

        def initialize(integration:, display_name:, notes_marker:)
          @display_name = display_name
          @notes_marker = notes_marker

          super(integration:)
        end

        def action_path
          "proxy/v3/company/#{ERB::Util.url_encode(integration.realm_id)}/query"
        end

        def call
          if integration.realm_id.blank?
            return result.service_failure!(code: "realm_id_missing", message: "QuickBooks connection has no company id")
          end

          throttle!(:quickbooks)

          response = http_client.get(headers:, params: {query:})
          customers = response.dig("QueryResponse", "Customer") if response.is_a?(Hash)
          customer = Array(customers).find { |c| c.is_a?(Hash) && c["Notes"].to_s.include?(notes_marker) }

          result.contact_id = customer["Id"].to_s if customer&.dig("Id").present?
          result
        rescue LagoHttpClient::HttpError => e
          log_nango_failure(LOOKUP_FAILURE_LOG, e, status: e.error_code)
          raise throttling_error(:quickbooks) if quickbooks_rate_limited?(e)

          lookup_failed
        rescue *LOOKUP_ERRORS => e
          log_nango_failure(LOOKUP_FAILURE_LOG, e)
          lookup_failed
        end

        private

        attr_reader :display_name, :notes_marker

        # QuickBooks query strings are quoted with single quotes, escaped with a backslash.
        def query
          "select Id, Notes from Customer where DisplayName = '#{display_name.gsub(/['\\]/) { |char| "\\#{char}" }}'"
        end

        def lookup_failed
          result.service_failure!(code: "customer_lookup_failed", message: "QuickBooks customer lookup failed")
        end
      end
    end
  end
end
