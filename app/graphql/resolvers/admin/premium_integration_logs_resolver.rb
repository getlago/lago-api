# frozen_string_literal: true

module Resolvers
  module Admin
    class PremiumIntegrationLogsResolver < Resolvers::BaseResolver
      include AuthenticableStaffUser

      description "Audit log of premium integration toggles for an organization (Lago staff only)"

      argument :organization_id, ID, required: true
      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::ActivityLogs::Object.collection_type, null: false

      def resolve(organization_id:, page: nil, limit: nil)
        Clickhouse::ActivityLog
          .where(
            organization_id: organization_id,
            activity_type: Clickhouse::ActivityLog::ACTIVITY_TYPES[:organization_premium_integration_toggled]
          )
          .order(logged_at: :desc)
          .page(page || 1)
          .per(limit || 25)
      end
    end
  end
end
