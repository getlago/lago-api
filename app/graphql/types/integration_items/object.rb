# frozen_string_literal: true

module Types
  module IntegrationItems
    class Object < Types::BaseObject
      graphql_name 'IntegrationItem'

      field :account_code, String, null: true
      field :external_id, String, null: false
      field :id, ID, null: false
      field :integration_id, ID, null: false
      field :item_type, Types::IntegrationItems::ItemTypeEnum, null: false
      field :name, String, null: true
    end
  end
end
