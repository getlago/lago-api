# frozen_string_literal: true

module Types
  module ActivityLogs
    class Object < Types::BaseObject
      graphql_name "ActivityLog"
      description "Base activity log"

      field :activity_id, ID, null: false
      field :activity_source, Types::ActivityLogs::ActivitySourceTypeEnum, null: false
      field :activity_type, Types::ActivityLogs::ActivityTypeTypeEnum, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :external_customer_id, String
      field :external_subscription_id, String
      field :logged_at, GraphQL::Types::ISO8601DateTime, null: false
      field :organization, Types::Organizations::OrganizationType
      field :resource_changes, String
      field :resource_id, String, null: false
      field :resource_type, String, null: false
      field :user, Types::UserType
    end
  end
end
