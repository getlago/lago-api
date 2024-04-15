# frozen_string_literal: true

module Types
  module Integrations
    class Okta < Types::BaseObject
      graphql_name 'OktaIntegration'

      field :client_id, String, null: true
      field :client_secret, String, null: true
      field :code, String, null: false
      field :domain, String, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :organization_name, String, null: false

      # NOTE: Client secret is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def client_secret
        "#{'•' * 8}…#{object.client_secret[-3..]}"
      end
    end
  end
end
