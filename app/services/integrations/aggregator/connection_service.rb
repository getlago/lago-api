# frozen_string_literal: true

module Integrations
  module Aggregator
    # NOTE: Reads the QuickBooks company id (realmId) of a Nango connection through GET /connection.
    #       The response also carries the OAuth credentials: nothing from it but the realm id
    #       may reach a result, a log or an error tracker.
    class ConnectionService < BaseService
      Result = BaseResult[:realm_id]

      LOOKUP_ERRORS = [
        LagoHttpClient::HttpError,
        JSON::ParserError,
        *LagoHttpClient::Client::TRANSIENT_ERROR_CLASSES
      ].freeze

      def action_path
        "connection/#{ERB::Util.url_encode(integration.connection_id)}"
      end

      def call
        response = http_client.get(headers:, params: {provider_config_key: provider_key})
        realm_id = realm_id_from(response)

        if realm_id.blank?
          result.single_validation_failure!(field: :realm_id, error_code: "value_is_mandatory")
        else
          result.realm_id = realm_id.to_s
          result
        end
      rescue *LOOKUP_ERRORS
        result.third_party_failure!(
          third_party: "Nango",
          error_code: "connection_lookup_failed",
          error_message: "QuickBooks connection lookup failed"
        )
      end

      private

      def realm_id_from(response)
        connection_config = response["connection_config"] if response.is_a?(Hash)

        if connection_config.is_a?(Hash)
          connection_config["realmId"]
        end
      end
    end
  end
end
