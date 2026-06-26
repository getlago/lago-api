# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module AuthenticableApiUser
  extend ActiveSupport::Concern

  private

  def ready?(**args)
    raise unauthorized_error unless context[:current_user]

    super
  end

  def unauthorized_error
    GraphQL::ExecutionError.new("unauthorized", extensions: {status: :unauthorized, code: "unauthorized"})
  end
end
