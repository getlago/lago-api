# frozen_string_literal: true

module Integrations
  module Aggregator
    class SubsidiariesService < BaseService
      def action_path
        "v1/#{provider}/subsidiaries"
      end

      def call
        response = http_client.get(headers:)

        result.subsidiaries = handle_subsidiaries(response["records"])

        result
      end

      private

      def headers
        {
          "Connection-Id" => integration.connection_id,
          "Authorization" => "Bearer #{secret_key}",
          "Provider-Config-Key" => provider_key
        }
      end

      def handle_subsidiaries(subsidiaries)
        subsidiaries.map do |subsidiary|
          OpenStruct.new(external_id: subsidiary["id"], external_name: subsidiary["name"])
        end
      end
    end
  end
end
