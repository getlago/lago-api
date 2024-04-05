# frozen_string_literal: true

module Types
  module Integrations
    class Netsuite < Types::BaseObject
      graphql_name 'NetsuiteIntegration'

      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :account_id, String, null: true
      field :client_id, String, null: true
      field :client_secret, String, null: true

      # NOTE: Client secret is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def client_secret
        "#{'•' * 8}…#{object.secret_key[-3..]}"
      end
    end
  end
end
