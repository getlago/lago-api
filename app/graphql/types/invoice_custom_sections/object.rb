# frozen_string_literal: true

module Types
  module InvoiceCustomSections
    class Object < Types::BaseObject
      graphql_name 'InvoiceCustomSection'

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: false
      field :description, String, null: true
      field :details, String, null: true
      field :display_name, String, null: true
      field :name, String, null: false

      field :selected, Boolean, null: false, method: :selected_for_organization?
    end
  end
end
