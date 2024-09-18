# frozen_string_literal: true

module Integrations
  module Aggregator
    class SendPrivateAppTokenService < BaseService
      def action_path
        "connection/#{integration.connection_id}/metadata"
      end

      def call
        return unless integration.type == 'Integrations::HubspotIntegration'
        return unless integration.private_app_token

        payload = {
          privateAppToken: integration.private_app_token
        }

        response = http_client.post_with_response(payload, headers)
        result.response = response

        result
      end

      private

      def headers
        {
          'Provider-Config-Key' => 'hubspot',
          'Authorization' => "Bearer #{secret_key}"
        }
      end
    end
  end
end
