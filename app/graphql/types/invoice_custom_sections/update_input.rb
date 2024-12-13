# frozen_string_literal: true

module Types
  module InvoiceCustomSections
    class UpdateInput < Types::BaseInputObject
      graphql_name 'UpdateInvoiceCustomSectionInput'

      argument :id, ID, required: true

      argument :description, String, required: false
      argument :details, String, required: false
      argument :display_name, String, required: false
      argument :name, String, required: false

      argument :selected, Boolean, required: false
    end
  end
end
