# frozen_string_literal: true

# ExecutionErrorResponder Module
module ExecutionErrorResponder
  extend ActiveSupport::Concern

  private

  def execution_error(error: 'Internal Error', status: 422, code: 'internal_error', details: nil)
    payload = {
      status: status,
      code: code,
    }

    if code == 'unprocessable_entity' && details.is_a?(Hash)
      payload[:details] = details&.transform_keys do |key|
        key.to_s.camelize(:lower)
      end
    end

    GraphQL::ExecutionError.new(error, extensions: payload)
  end

  def not_found_error(code:)
    execution_error(
      error: 'Resource not found',
      status: 404,
      code: code,
    )
  end

  def result_error(service_result)
    return not_found_error(code: service_result.error.code) if service_result.error.is_a?(BaseService::NotFoundFailure)

    execution_error(
      code: service_result.error_code,
      error: service_result.error,
      details: service_result.error_details,
    )
  end
end
