# frozen_string_literal: true

module Types
  module InvoiceCustomSections
    class Object < Types::BaseObject
      graphql_name 'InvoiceCustomSection'

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: true
      field :description, String, null: true
      field :details, String, null: true
      field :display_name, String, null: false
      field :name, String, null: false

      field :selected, Boolean, null: true

      def selected
        object.selected_for_organization?
      end
    end
  end
end
