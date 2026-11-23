# frozen_string_literal: true

module Types
  module Integrations
    class Quickbooks < Types::BaseObject
      graphql_name "QuickbooksIntegration"

      field :code, String, null: false
      field :connection_id, ID, null: false
      field :has_mappings_configured, Boolean
      field :id, ID, null: false
      field :name, String, null: false
      field :realm_id, String
      field :sandbox, Boolean, null: false, method: :sandbox?
      field :sync_credit_notes, Boolean
      field :sync_invoices, Boolean
      field :sync_payments, Boolean

      # IntegrationCollectionMappings::QuickbooksCollectionMapping does not exist yet:
      # this returns false until the QuickBooks mapping model lands.
      def has_mappings_configured
        object.integration_collection_mappings.where(type: "IntegrationCollectionMappings::QuickbooksCollectionMapping").any?
      end
    end
  end
end
