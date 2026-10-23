# frozen_string_literal: true

module Api
  module V2
    class ApiLogsController < Api::V2::BaseController
      include PremiumFeatureOnly

      skip_audit_logs!

      cursor_paginated_index(Clickhouse::ApiLog, sort: {logged_at: :desc, request_id: :desc})

      def index
        result = ApiLogsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: index_filters
        )

        if result.success?
          page = ::CursorPagination::Page.new(records: result.api_logs, cursor:)

          render(
            json: ::CollectionSerializer.new(
              page.records,
              ::V2::ApiLogSerializer,
              collection_name: "api_logs",
              meta: page.meta
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        api_log = current_organization.api_logs.find_by(
          request_id: params[:request_id]
        )

        return not_found_error(resource: "api_log") unless api_log

        render(
          json: ::V2::ApiLogSerializer.new(
            api_log,
            root_name: "api_log"
          )
        )
      end

      private

      def resource_name
        "api_log"
      end

      def index_filters
        {
          from_date: params[:from_date],
          to_date: params[:to_date],
          http_methods: params[:http_methods],
          http_statuses: params[:http_statuses],
          api_version: params[:api_version],
          request_paths: params[:request_paths],
          clients: params[:clients]
        }
      end
    end
  end
end
