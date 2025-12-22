# frozen_string_literal: true

module Types
  module Integrations
    class NetsuiteV2
      class CreateInput < Types::BaseInputObject
        graphql_name "CreateNetsuiteV2IntegrationInput"

        argument :code, String, required: true
        argument :name, String, required: true

        argument :account_id, String, required: true
        argument :client_id, String, required: true
        argument :client_secret, String, required: true
        argument :script_endpoint_url, String, required: true
        argument :token_id, String, required: true
        argument :token_secret, String, required: true

        argument :sync_credit_notes, Boolean, required: false
        argument :sync_invoices, Boolean, required: false
        argument :sync_payments, Boolean, required: false
      end
    end
  end
end
