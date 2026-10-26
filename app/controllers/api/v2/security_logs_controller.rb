# frozen_string_literal: true

module Api
  module V2
    class SecurityLogsController < Api::V2::BaseController
      include PremiumFeatureOnly

      skip_audit_logs!

      before_action :ensure_security_logs_enabled

      cursor_paginated_index(Clickhouse::SecurityLog, sort: {logged_at: :desc, log_id: :desc})
      serializable_with ::V2::SecurityLogSerializer

      def index
        result = ::SecurityLogsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: index_filters
        )

        if result.success?
          render_security_logs(result.security_logs)
        else
          render_error_response(result)
        end
      end

      def show
        security_log = current_organization.security_logs.find_by(log_id: params[:log_id])

        return not_found_error(resource: "security_log") unless security_log

        render_security_log(security_log)
      end

      private

      def ensure_security_logs_enabled
        forbidden_error(code: "forbidden") unless current_organization.security_logs_enabled?
      end

      def resource_name
        "security_log"
      end

      def index_filters
        params.permit(
          :from_date,
          :to_date,
          user_ids: [],
          api_key_ids: [],
          log_types: [],
          log_events: []
        )
      end
    end
  end
end
