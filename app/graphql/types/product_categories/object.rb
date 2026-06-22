# frozen_string_literal: true

module Types
  module ProductCategories
    class Object < Types::BaseObject
      graphql_name "ProductCategory"
      description "Base product_category"

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: false
      field :description, String, null: true
      field :invoice_display_name, String, null: true
      field :name, String, null: false

      field :attached_to_plan_or_subscription, Boolean, null: false, method: :attached_to_plan_or_subscription?
      field :products_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def products_count
        object.products.count
      end
    end
  end
end
