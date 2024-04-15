# frozen_string_literal: true

module Types
  module IntegrationMappings
    module Netsuite
      class Object < Types::BaseObject
        graphql_name 'NetsuiteMapping'

        field :id, ID, null: false
        field :integration_id, ID, null: false
        field :mappable_id, ID, null: false
        field :mappable_type, Types::IntegrationMappings::Netsuite::MappableTypeEnum, null: false
        field :netsuite_account_code, String, null: false
        field :netsuite_id, String, null: false
        field :netsuite_name, String, null: true
      end
    end
  end
end
