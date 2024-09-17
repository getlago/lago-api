# frozen_string_literal: true

module Graphql
  class ApiController < BaseController
    include AuthenticableUser
    include OrganizationHeader
    include Trackable

    def execute
      variables = prepare_variables(params[:variables])
      query = params[:query]
      operation_name = params[:operationName]
      context = {
        current_user:,
        current_organization:,
        request:,
        permissions:
          current_user&.memberships&.find_by(organization: current_organization)&.permissions_hash ||
            Permission::EMPTY_PERMISSIONS_HASH
      }

      OpenTelemetry::Trace.current_span.add_attributes({"query" => query, "operation_name" => operation_name})
      result = LagoTracer.in_span("Schemas::ApiSchema.execute") do
        Schemas::ApiSchema.execute(query, variables:, context:, operation_name:)
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
