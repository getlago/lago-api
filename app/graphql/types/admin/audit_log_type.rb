# frozen_string_literal: true

module Types
  module Admin
    class AuditLogType < Types::BaseObject
      graphql_name "AdminAuditLog"

      field :action, Types::Admin::ActionEnum, null: false
      field :actor_email, String, null: false
      field :after_value, Boolean, null: false
      field :batch_id, ID, null: true
      field :before_value, Boolean, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :feature_key, String, null: false
      field :feature_type, Types::Admin::FeatureTypeEnum, null: false
      field :id, ID, null: false
      field :organization_id, ID, null: false
      field :organization_name, String, null: false
      field :reason, String, null: false
      field :rollback_of_id, ID, null: true

      def organization_name
        object.organization.name
      end
    end
  end
end
