# frozen_string_literal: true

module Api
  module V2
    class ActivityLogsController < Api::V2::BaseController
      include PremiumFeatureOnly

      skip_audit_logs!

      cursor_paginated_index(Clickhouse::ActivityLog, sort: {logged_at: :desc, activity_id: :desc})
      serializable_with ::V2::ActivityLogSerializer

      def index
        result = ActivityLogsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: index_filters
        )

        if result.success?
          render_activity_logs(result.activity_logs)
        else
          render_error_response(result)
        end
      end

      def show
        activity_log = current_organization.activity_logs.find_by(activity_id: params[:activity_id])

        return not_found_error(resource: "activity_log") unless activity_log

        render_activity_log(activity_log)
      end

      private

      def resource_name
        "activity_log"
      end

      def index_filters
        params.permit(
          :from_date,
          :to_date,
          :external_customer_id,
          :external_subscription_id,
          activity_types: [],
          activity_sources: [],
          user_emails: [],
          resource_ids: [],
          resource_types: []
        )
      end
    end
  end
end
