# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module AuthenticableCustomerPortalUser
  extend ActiveSupport::Concern

  private

  def ready?(**args)
    raise unauthorized_error unless context[:customer_portal_user]

    super
  end

  def unauthorized_error
    GraphQL::ExecutionError.new("unauthorized", extensions: {status: :unauthorized, code: "unauthorized"})
  end
end
