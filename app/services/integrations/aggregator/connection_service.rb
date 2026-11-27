# frozen_string_literal: true

module Integrations
  module Aggregator
    # NOTE: Reads the QuickBooks company id (realmId) of a Nango connection through GET /connection.
    #       The response also carries the OAuth credentials: nothing from it but the realm id
    #       may reach a result, a log or an error tracker.
    #       It runs inside a GraphQL request, so the HTTP client has short timeouts and no retry.
    class ConnectionService < BaseService
      Result = BaseResult[:realm_id]

      LOOKUP_FAILURE_LOG = "QuickBooks connection lookup failed"

      def action_path
        "connection/#{ERB::Util.url_encode(integration.connection_id)}"
      end

      def call
        response = http_client.get(headers:, params: {provider_config_key: provider_key})
        realm_id = realm_id_from(response)

        if realm_id.blank?
          result.third_party_failure!(
            third_party: "Nango",
            error_code: "realm_id_missing",
            error_message: "QuickBooks connection has no company id"
          )
        else
          result.realm_id = realm_id.to_s
          result
        end
      rescue LagoHttpClient::HttpError => e
        log_nango_failure(LOOKUP_FAILURE_LOG, e, status: e.error_code)

        if e.error_code.to_i == 404
          result.third_party_failure!(
            third_party: "Nango",
            error_code: "connection_not_found",
            error_message: "QuickBooks connection not found for this environment"
          )
        else
          lookup_failed
        end
      rescue *LOOKUP_ERRORS => e
        log_nango_failure(LOOKUP_FAILURE_LOG, e)
        lookup_failed
      end

      private

      def http_client
        # max_retries: 0 turns off Net::HTTP's own retry of an idempotent GET after a read timeout.
        LagoHttpClient::Client.new(endpoint_url, open_timeout: 5, read_timeout: 10, write_timeout: 10, max_retries: 0)
      end

      def realm_id_from(response)
        connection_config = response["connection_config"] if response.is_a?(Hash)

        if connection_config.is_a?(Hash)
          connection_config["realmId"]
        end
      end

      def lookup_failed
        result.third_party_failure!(
          third_party: "Nango",
          error_code: "connection_lookup_failed",
          error_message: "QuickBooks connection lookup failed"
        )
      end
    end
  end
end
