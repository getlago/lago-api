# frozen_string_literal: true

module Types
  module Integrations
    class Quickbooks
      class CreateInput < Types::BaseInputObject
        graphql_name "CreateQuickbooksIntegrationInput"

        argument :code, String, required: true
        argument :name, String, required: true

        argument :connection_id, String, required: true
        argument :sandbox, Boolean, required: false

        argument :sync_credit_notes, Boolean, required: false
        argument :sync_invoices, Boolean, required: false
        argument :sync_payments, Boolean, required: false
      end
    end
  end
end
