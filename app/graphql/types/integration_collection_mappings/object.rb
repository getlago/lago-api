# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    class Object < Types::BaseObject
      graphql_name "CollectionMapping"

      field :external_account_code, String, null: true
      field :external_id, String, null: false
      field :external_name, String, null: true
      field :id, ID, null: false
      field :integration_id, ID, null: false
      field :mapping_type, Types::IntegrationCollectionMappings::MappingTypeEnum, null: false
      field :tax_code, String, null: true
      field :tax_nexus, String, null: true
      field :tax_type, String, null: true
    end
  end
end
