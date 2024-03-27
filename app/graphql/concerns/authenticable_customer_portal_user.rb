# frozen_string_literal: true

module AuthenticableCustomerPortalUser
  extend ActiveSupport::Concern

  private

  def ready?(*)
    return true if context[:customer_portal_user]

    raise unauthorized_error
  end

  def unauthorized_error
    GraphQL::ExecutionError.new("unauthorized", extensions: {status: :unauthorized, code: "unauthorized"})
  end
end
