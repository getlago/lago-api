# frozen_string_literal: true

module Integrations
  module Aggregator
    class SendRestletEndpointService < BaseService
      def action_path
        "connection/#{integration.connection_id}/metadata"
      end

      def call
        return unless integration.type == 'Integrations::NetsuiteIntegration'

        payload = {
          restletEndpoint: integration.script_endpoint_url,
        }

        response = http_client.post_with_response(payload, headers)
        result.response = response

        result
      end

      private

      def headers
        {
          'Provider-Config-Key' => 'netsuite',
          'Authorization' => "Bearer #{secret_key}",
        }
      end
    end
  end
end
