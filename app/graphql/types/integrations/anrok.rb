# frozen_string_literal: true

module Types
  module Integrations
    class Anrok < Types::BaseObject
      graphql_name 'AnrokIntegration'

      field :api_key, String, null: false
      field :code, String, null: false
      field :has_mappings_configured, Boolean
      field :id, ID, null: false
      field :name, String, null: false

      # NOTE: Client secret is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def api_key
        "#{"•" * 8}…#{object.api_key[-3..]}"
      end

      def has_mappings_configured
        object.integration_collection_mappings.where(type: 'IntegrationCollectionMappings::AnrokCollectionMapping').any?
      end
    end
  end
end
