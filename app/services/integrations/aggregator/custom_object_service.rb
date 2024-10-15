# frozen_string_literal: true

module Integrations
  module Aggregator
    class CustomObjectService < BaseService
      def initialize(integration:, name:)
        @name = name
        super(integration:)
      end

      def action_path
        "v1/#{provider}/custom-object"
      end

      def call
        response = http_client.get(headers:, params:)

        result.custom_object = OpenStruct.new(response)
        result
      end

      private

      attr_reader :name

      def headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}",
          'Provider-Config-Key' => provider_key
        }
      end

      def params
        {
          'name' => name
        }
      end
    end
  end
end
