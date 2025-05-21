# frozen_string_literal: true

module Types
  module ActivityLogs
    class Object < Types::BaseObject
      graphql_name "ActivityLog"
      description "Base activity log"

      field :activity_id, ID, null: false
      field :activity_object, GraphQL::Types::JSON
      field :activity_object_changes, GraphQL::Types::JSON
      field :activity_source, Types::ActivityLogs::ActivitySourceEnum, null: false
      field :activity_type, Types::ActivityLogs::ActivityTypeEnum, null: false
      field :api_key_id, ID
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :external_customer_id, String
      field :external_subscription_id, String
      field :logged_at, GraphQL::Types::ISO8601DateTime, null: false
      field :organization, Types::Organizations::OrganizationType
      field :resource, GraphQL::Types::JSON
      field :resource_type, String, null: false
      field :user_email, String

      def user_email
        object.user.email
      end

      def resource
        "V1::#{object.resource_type}Serializer".constantize.new(object.resource).serialize
      end
    end
  end
end
