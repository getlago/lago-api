# frozen_string_literal: true

class GraphqlController < ApplicationController
  include AuthenticableUser
  include CustomerPortalUser
  include OrganizationHeader
  include Trackable

  before_action :set_context_source

  rescue_from JWT::ExpiredSignature do
    render_graphql_error(code: "expired_jwt_token", status: 401)
  end

  # If accessing from outside this domain, nullify the session
  # This allows for outside API access while preventing CSRF attacks,
  # but you'll have to authenticate your user separately
  # protect_from_forgery with: :null_session

  def execute
    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]
    context = {
      current_user:,
      current_organization:,
      customer_portal_user:,
      request:
    }
    result = LagoApiSchema.execute(query, variables:, context:, operation_name:)
    render(json: result)
  rescue JWT::ExpiredSignature
    render_graphql_error(code: "expired_jwt_token", status: 401)
  rescue => e
    raise e unless Rails.env.development?

    handle_error_in_development(e)
  end

  private

  # Handle variables in form data, JSON body, or a blank value
  def prepare_variables(variables_param)
    case variables_param
    when String
      if variables_param.present?
        JSON.parse(variables_param) || {}
      else
        {}
      end
    when Hash
      variables_param
    when ActionController::Parameters
      variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{variables_param}"
    end
  end

  def handle_error_in_development(e)
    logger.error(e.message)
    logger.error(e.backtrace.join("\n"))

    render(json: {errors: [{message: e.message, backtrace: e.backtrace}], data: {}}, status: 500)
  end

  def render_graphql_error(code:, status:, message: nil)
    render(
      json: {
        data: {},
        errors: [
          {
            message: message || code,
            extensions: {status:, code:}
          }
        ]
      }
    )
  end

  def set_context_source
    CurrentContext.source = "graphql"
  end
end
