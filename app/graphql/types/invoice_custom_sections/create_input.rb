# frozen_string_literal: true

module Types
  module InvoiceCustomSections
    class CreateInput < Types::BaseInputObject
      graphql_name 'CreateInvoiceCustomSectionInput'

      argument :code, String, required: true
      argument :description, String, required: false
      argument :details, String, required: false
      argument :display_name, String, required: false
      argument :name, String, required: true

      argument :selected, Boolean, required: false
    end
  end
end
