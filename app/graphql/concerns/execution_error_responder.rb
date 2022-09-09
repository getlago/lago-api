# frozen_string_literal: true

# ExecutionErrorResponder Module
module ExecutionErrorResponder
  extend ActiveSupport::Concern

  private

  def execution_error(message: 'Internal Error', status: 422, code: 'internal_error', details: nil)
    payload = {
      status: status,
      code: code,
    }

    if code == 'unprocessable_entity' && details.is_a?(Hash)
      payload[:details] = details&.transform_keys do |key|
        key.to_s.camelize(:lower)
      end
    end

    GraphQL::ExecutionError.new(message, extensions: payload)
  end

  def not_found_error
    execution_error(
      message: 'Resource not found',
      status: 404,
      code: 'not_found',
    )
  end

  def result_error(service_result)
    execution_error(
      code: service_result.error_code,
      message: service_result.error,
      details: service_result.error_details,
    )
  end
end
