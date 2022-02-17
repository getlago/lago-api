# frozen_string_literal: true

# ExecutionErrorResponder Module
module ExecutionErrorResponder
  extend ActiveSupport::Concern

  private

  def execution_error(message: 'Internal Error', status: 422, code: 'internal_error')
    GraphQL::ExecutionError.new(message, options: { status: status, code: code })
  end
end
