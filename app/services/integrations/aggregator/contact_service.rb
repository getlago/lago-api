# frozen_string_literal: true

module Integrations
  module Aggregator
    class ContactService < BaseService
      def action_path
        "v1/#{provider}/contacts/#{id}"
      end

      def call
        raise 'ID is not present' if id.blank?

        response = http_client.get(headers:)

        result.contact = handle_attributes(response)

        result
      end

      private

      def headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}",
          'Provider-Config-Key' => provider,
        }
      end

      def handle_attributes(contact)
        OpenStruct.new(
          external_id: contact['id'],
          external_name: contact['name'],
          subsidiary_id: contact['subsidiary'].first['value'],
        )
      end
    end
  end
end
