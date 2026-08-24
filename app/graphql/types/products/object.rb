# frozen_string_literal: true

module Types
  module Products
    class Object < Types::BaseObject
      graphql_name "Product"
      description "Base product"

      dataload_association :product_category, :billable_metric

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :attached_to_plan_or_subscription, Boolean, null: false
      field :code, String, null: false
      field :description, String, null: true
      field :invoice_display_name, String, null: true
      field :name, String, null: false
      field :product_type, Types::Products::ProductTypeEnum, null: false

      field :billable_metric, Types::BillableMetrics::Object, null: true
      field :integration_mappings, [Types::IntegrationMappings::Object], null: true do
        argument :integration_id, ID, required: false
      end
      field :product_category, Types::ProductCategories::Object, null: true

      field :filters_count, Integer, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def attached_to_plan_or_subscription
        dataloader.with(Sources::AttachedToPlanOrSubscription, :product).load(object.id)
      end

      def filters_count
        dataloader.with(Sources::CountByForeignKey, ProductFilter, :product_id).load(object.id)
      end

      def integration_mappings(integration_id: nil)
        mappings = dataloader.with(Sources::ActiveRecordAssociation, :integration_mappings).load(object)
        return mappings unless integration_id

        mappings.select { |mapping| mapping.integration_id == integration_id }
      end
    end
  end
end
