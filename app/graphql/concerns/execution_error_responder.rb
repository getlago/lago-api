# frozen_string_literal: true

# ExecutionErrorResponder Module
module ExecutionErrorResponder
  extend ActiveSupport::Concern

  private

  def execution_error(message: 'Internal Error', status: 422, code: 'internal_error')
    GraphQL::ExecutionError.new(message, extensions: { status: status, code: code })
  end

  def not_found_error
    execution_error(
      message: 'Resource not found',
      status: 404,
      code: 'not_found',
    )
  end
end
