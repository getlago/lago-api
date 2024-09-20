# frozen_string_literal: true

module Graphql
  class CustomerPortalController < BaseController
    include CustomerPortalUser

    def execute
      variables = prepare_variables(params[:variables])
      query = params[:query]
      operation_name = params[:operationName]
      context = {
        customer_portal_user:,
        request:
      }

      OpenTelemetry::Trace.current_span.add_attributes({"query" => query, "operation_name" => operation_name})
      result = LagoTracer.in_span("Schemas::CustomerPortalSchema.execute") do
        Schemas::CustomerPortalSchema.execute(query, variables:, context:, operation_name:)
      end

      render(json: result)
    rescue JWT::ExpiredSignature
      render_graphql_error(code: "expired_jwt_token", status: 401)
    rescue => e
      raise e unless Rails.env.development?

      handle_error_in_development(e)
    end
  end
end
