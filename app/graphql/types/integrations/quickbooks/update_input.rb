# frozen_string_literal: true

module Types
  module Integrations
    class Quickbooks
      class UpdateInput < Types::BaseInputObject
        graphql_name "UpdateQuickbooksIntegrationInput"

        argument :id, ID, required: true

        argument :code, String, required: false
        argument :name, String, required: false

        argument :sync_credit_notes, Boolean, required: false
        argument :sync_invoices, Boolean, required: false
        argument :sync_payments, Boolean, required: false
      end
    end
  end
end
