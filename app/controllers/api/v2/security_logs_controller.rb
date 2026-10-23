# frozen_string_literal: true

module Api
  module V2
    class SecurityLogsController < Api::V2::BaseController
      include PremiumFeatureOnly

      skip_audit_logs!

      before_action :ensure_security_logs_enabled

      cursor_paginated_index(Clickhouse::SecurityLog, sort: {logged_at: :desc, log_id: :desc})

      def index
        result = ::SecurityLogsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: index_filters
        )

        if result.success?
          page = ::CursorPagination::Page.new(records: result.security_logs, cursor:)

          render(
            json: ::CollectionSerializer.new(
              page.records,
              ::V2::SecurityLogSerializer,
              collection_name: "security_logs",
              meta: page.meta
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        security_log = current_organization.security_logs.find_by(log_id: params[:log_id])

        return not_found_error(resource: "security_log") unless security_log

        render(json: ::V2::SecurityLogSerializer.new(security_log, root_name: "security_log"))
      end

      private

      def ensure_security_logs_enabled
        forbidden_error(code: "forbidden") unless current_organization.security_logs_enabled?
      end

      def resource_name
        "security_log"
      end

      def index_filters
        {
          from_date: params[:from_date],
          to_date: params[:to_date],
          user_ids: params[:user_ids],
          api_key_ids: params[:api_key_ids],
          log_types: params[:log_types],
          log_events: params[:log_events]
        }
      end
    end
  end
end
