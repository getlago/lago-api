# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    module Netsuite
      class Object < Types::BaseObject
        graphql_name 'NetsuiteCollectionMapping'

        field :id, ID, null: false
        field :integration_id, ID, null: false
        field :mapping_type, Types::IntegrationCollectionMappings::Netsuite::MappingTypeEnum, null: false
        field :netsuite_account_code, String, null: false
        field :netsuite_id, String, null: false
        field :netsuite_name, String, null: true
      end
    end
  end
end
