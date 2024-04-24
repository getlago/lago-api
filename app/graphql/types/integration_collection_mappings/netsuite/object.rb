# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    module Netsuite
      class Object < Types::BaseObject
        graphql_name 'NetsuiteCollectionMapping'

        field :external_account_code, String, null: true
        field :external_id, String, null: false
        field :external_name, String, null: true
        field :id, ID, null: false
        field :integration_id, ID, null: false
        field :mapping_type, Types::IntegrationCollectionMappings::Netsuite::MappingTypeEnum, null: false
      end
    end
  end
end
