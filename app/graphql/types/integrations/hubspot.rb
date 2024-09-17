# frozen_string_literal: true

module Types
  module Integrations
    class Hubspot < Types::BaseObject
      graphql_name 'HubspotIntegration'

      field :code, String, null: false
      field :connection_id, ID, null: false
      field :default_targeted_object, Types::Integrations::Hubspot::TargetedObjectsEnum, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :private_app_token, String, null: false
      field :sync_invoices, Boolean
      field :sync_subscriptions, Boolean
    end
  end
end
