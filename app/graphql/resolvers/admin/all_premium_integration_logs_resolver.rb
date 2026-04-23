# frozen_string_literal: true

module Resolvers
  module Admin
    class AllPremiumIntegrationLogsResolver < Resolvers::BaseResolver
      include AuthenticableStaffUser

      description "Every premium-integration toggle log across all organizations (Lago staff only). Optional searchTerm filters by org id (UUID) or name (case-insensitive LIKE)."

      argument :search_term, String, required: false
      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::ActivityLogs::Object.collection_type, null: false

      def resolve(search_term: nil, page: nil, limit: nil)
        scope = Clickhouse::ActivityLog
          .where(activity_type: Clickhouse::ActivityLog::ACTIVITY_TYPES[:organization_premium_integration_toggled])
          .order(logged_at: :desc)

        if search_term.present?
          org_ids = matching_organization_ids(search_term)
          scope = scope.where(organization_id: org_ids)
        end

        effective_limit = limit.presence || 10_000
        scope.page(page || 1).per(effective_limit.clamp(1, 10_000))
      end

      private

      def matching_organization_ids(term)
        term = term.to_s.strip
        return [term] if uuid?(term)

        like = "%#{term.downcase}%"
        ::Organization.where("LOWER(name) LIKE ?", like).pluck(:id)
      end

      def uuid?(value)
        value.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end
    end
  end
end
