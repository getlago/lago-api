# frozen_string_literal: true

require 'lago_http_client'

module Integrations
  module Aggregator
    class BaseService < BaseService
      BASE_URL = 'https://api.nango.dev/'

      def initialize(integration:)
        @integration = integration

        super
      end

      def action_path
        raise NotImplementedError
      end

      private

      attr_reader :integration

      def http_client
        LagoHttpClient::Client.new(endpoint_url)
      end

      def endpoint_url
        "#{BASE_URL}#{action_path}"
      end

      def generate_headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}",
        }
      end

      def secret_key
        ENV['NANGO_SECRET_KEY']
      end
    end
  end
end
