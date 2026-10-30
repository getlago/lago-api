# frozen_string_literal: true

module Api
  module V2
    class ApiLogsController < Api::V2::BaseController
      include PremiumFeatureOnly

      skip_audit_logs!

      cursor_paginated_index(Clickhouse::ApiLog, sort: {logged_at: :desc, request_id: :desc})
      serializable_with ::V2::ApiLogSerializer

      def index
        result = ApiLogsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: index_filters
        )

        if result.success?
          render_api_logs(result.api_logs)
        else
          render_error_response(result)
        end
      end

      def show
        api_log = current_organization.api_logs.find_by(request_id: params[:request_id])

        return not_found_error(resource: "api_log") unless api_log

        render_api_log(api_log)
      end

      private

      def resource_name
        "api_log"
      end

      def index_filters
        params.permit(
          :from_date,
          :to_date,
          :api_version,
          http_methods: [],
          http_statuses: [],
          request_paths: [],
          clients: []
        )
      end
    end
  end
end
