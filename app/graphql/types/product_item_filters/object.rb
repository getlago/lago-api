# frozen_string_literal: true

module Types
  module ProductItemFilters
    class Object < Types::BaseObject
      graphql_name "ProductItemFilter"
      description "Base product item filter"

      dataload_association :product_item

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :attached_to_plan_or_subscription, Boolean, null: false, method: :attached_to_plan_or_subscription?
      field :code, String, null: false
      field :description, String, null: true
      field :invoice_display_name, String, null: true
      field :name, String, null: false

      field :product_item, Types::ProductItems::Object, null: false
      field :values, [Types::ProductItemFilterValues::Object], null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
