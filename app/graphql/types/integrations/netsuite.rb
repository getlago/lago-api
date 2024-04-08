# frozen_string_literal: true

module Types
  module Integrations
    class Netsuite < Types::BaseObject
      graphql_name 'NetsuiteIntegration'

      field :account_id, String, null: true
      field :client_id, String, null: true
      field :client_secret, String, null: true
      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :sync_credit_notes, Boolean
      field :sync_invoices, Boolean
      field :sync_payments, Boolean
      field :sync_sales_orders, Boolean

      # NOTE: Client secret is a sensitive information. It should not be sent back to the
      #       front end application. Instead we send an obfuscated value
      def client_secret
        "#{'•' * 8}…#{object.client_secret[-3..]}"
      end
    end
  end
end
