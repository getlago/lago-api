# frozen_string_literal: true

module Types
  module ProductItems
    class Object < Types::BaseObject
      graphql_name "ProductItem"
      description "Base product item"

      dataload_association :product, :billable_metric

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: false
      field :description, String, null: true
      field :invoice_display_name, String, null: true
      field :item_type, Types::ProductItems::ItemTypeEnum, null: false
      field :name, String, null: false

      field :billable_metric, Types::BillableMetrics::Object, null: true
      field :product, Types::Products::Object, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
