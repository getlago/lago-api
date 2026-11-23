# frozen_string_literal: true

module Integrations
  module Aggregator
    # NOTE: Reads the QuickBooks company id (realmId) of a Nango connection through GET /connection.
    #       The response also carries the OAuth credentials: nothing from it but the realm id
    #       may reach a result, a log or an error tracker.
    #       It runs inside a GraphQL request, so the HTTP client has short timeouts and no retry.
    class ConnectionService < BaseService
      Result = BaseResult[:realm_id]

      LOOKUP_ERRORS = [
        JSON::ParserError,
        *LagoHttpClient::Client::TRANSIENT_ERROR_CLASSES,
        *LagoHttpClient::Client::CONNECT_FALLBACK_ERRORS
      ].uniq.freeze

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
        log_lookup_failure(e, status: e.error_code)

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
        log_lookup_failure(e)
        lookup_failed
      end

      private

      def http_client
        LagoHttpClient::Client.new(endpoint_url, open_timeout: 5, read_timeout: 10, write_timeout: 10)
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

      # Never the response body, the headers or the connection id: they can hold OAuth credentials.
      def log_lookup_failure(error, status: nil)
        details = {
          organization_id: integration.organization_id,
          provider_config_key: provider_key,
          error: error.class.name,
          status:
        }.compact

        Rails.logger.warn("QuickBooks connection lookup failed #{details.to_json}")
      end
    end
  end
end
