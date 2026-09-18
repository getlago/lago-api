# frozen_string_literal: true

module Resolvers
  module Admin
    class AuditLogsResolver < Resolvers::BaseResolver
      include AuthenticableAdminUser

      description "Query admin audit logs with filters"

      argument :actions, [Types::Admin::ActionEnum], required: false
      argument :actor_user_ids, [ID], required: false
      argument :feature_key, String, required: false
      argument :feature_type, Types::Admin::FeatureTypeEnum, required: false
      argument :from_date, GraphQL::Types::ISO8601Date, required: false
      argument :limit, Integer, required: false
      argument :organization_ids, [ID], required: false
      argument :page, Integer, required: false
      argument :to_date, GraphQL::Types::ISO8601Date, required: false

      type Types::Admin::AuditLogType.collection_type, null: false

      def resolve(**args)
        logs = CsAdminAuditLog.newest_first.includes(:organization, :rollback)

        logs = logs.where(organization_id: args[:organization_ids]) if args[:organization_ids].present?
        logs = logs.where(actor_user_id: args[:actor_user_ids]) if args[:actor_user_ids].present?
        logs = logs.where(action: args[:actions]) if args[:actions].present?
        logs = logs.where(feature_key: args[:feature_key]) if args[:feature_key]
        logs = logs.where(feature_type: args[:feature_type]) if args[:feature_type]
        logs = logs.where("created_at >= ?", args[:from_date].beginning_of_day) if args[:from_date]
        logs = logs.where("created_at <= ?", args[:to_date].end_of_day) if args[:to_date]

        logs.page(args[:page]).per(args[:limit] || 25)
      end
    end
  end
end
