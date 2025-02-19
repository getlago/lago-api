# frozen_string_literal: true

module ApiErrors
  extend ActiveSupport::Concern

  def bad_request_error(error)
    render(
      json: {
        status: 400,
        error: "BadRequest: #{error.message}"
      },
      status: :bad_request
    )
  end

  def unauthorized_error(message: "Unauthorized")
    render(
      json: {
        status: 401,
        error: message
      },
      status: :unauthorized
    )
  end

  def validation_errors(errors:)
    render(
      json: {
        status: 422,
        error: "Unprocessable Entity",
        code: "validation_errors",
        error_details: errors
      },
      status: :unprocessable_entity
    )
  end

  def forbidden_error(code:)
    render(
      json: {
        status: 403,
        error: "Forbidden",
        code:
      },
      status: :forbidden
    )
  end

  def method_not_allowed_error(code:)
    render(
      json: {
        status: 405,
        error: "Method Not Allowed",
        code:
      },
      status: :method_not_allowed
    )
  end

  def payment_provider_error(error_result)
    render(
      json: {
        status: error_result.status,
        error: error_result.message,
        payment_provider: error_result.payment_provider,
        payment_provider_code: error_result.payment_provider_code,
        details: error_result.details
      },
      status: error_result.status
    )
  end

  def thirdparty_error(error:)
    render(
      json: {
        status: 422,
        error: "Unprocessable Entity",
        code: "third_party_error",
        error_details: {
          third_party: error.third_party,
          thirdparty_error: error.error_message
        }
      }
    )
  end

  def render_error_response(error_result)
    case error_result.error
    when BaseService::NotFoundFailure
      not_found_error(resource: error_result.error.resource)
    when BaseService::MethodNotAllowedFailure
      method_not_allowed_error(code: error_result.error.code)
    when BaseService::ValidationFailure
      validation_errors(errors: error_result.error.messages)
    when BaseService::ForbiddenFailure
      forbidden_error(code: error_result.error.code)
    when BaseService::UnauthorizedFailure
      unauthorized_error(message: error_result.error.message)
    when BaseService::PaymentProviderFailure
      payment_provider_error(error_result.error)
    when BaseService::ThirdPartyFailure
      thirdparty_error(error: error_result.error)
    else
      raise(error_result.error)
    end
  end
end
