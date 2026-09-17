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

      field :attached_to_plan_or_subscription, Boolean, null: false
      field :products_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def attached_to_plan_or_subscription
        dataloader.with(Sources::AttachedToPlanOrSubscription, :product_category).load(object.id)
      end

      def products_count
        dataloader.with(Sources::CountByForeignKey, Product, :product_category_id).load(object.id)
      end
    end
  end
end
