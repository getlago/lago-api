# frozen_string_literal: true

module Types
  module AttributedUsage
    class Object < Types::BaseObject
      graphql_name "AttributedUsage"

      field :external_subscription_id, String, null: false
      field :group_by, String, null: false
      field :subscription_id, ID, null: false

      field :basis, Types::AttributedUsage::BasisEnum, null: false
      field :currency, Types::CurrencyEnum, null: false
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false

      field :rows, [Types::AttributedUsage::Row], null: false
      field :totals, Types::AttributedUsage::Aggregate, null: false
      field :unattributed, Types::AttributedUsage::Aggregate, null: false

      field :metadata, GraphqlPagination::CollectionMetadataType, null: false

      def subscription_id
        object.subscription.id
      end

      def external_subscription_id
        object.subscription.external_id
      end

      def metadata
        UsageAttributions::Page.from_query_result(object)
      end
    end
  end
end
