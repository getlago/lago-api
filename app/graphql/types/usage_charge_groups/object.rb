# frozen_string_literal: true

module Types
  module UsageChargeGroups
    class Object < Types::BaseObject
      graphql_name 'UsageChargeGroup'

      field :id, ID, null: false

      field :charge_group, Types::ChargeGroups::Object, null: false
      field :subscription, Types::Subscriptions::Object, null: false

      field :available_group_usage, GraphQL::Types::JSON, null: true
      field :current_package_count, GraphQL::Types::BigInt, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      # TODO: check if this is needed
      def charge_group
        return object.charge_group unless object.discarded?

        ChargeGroup.with_discarded.find_by(id: object.charge_group_id)
      end

      # TODO: check if this is needed
      delegate :subscription, to: :object
    end
  end
end
