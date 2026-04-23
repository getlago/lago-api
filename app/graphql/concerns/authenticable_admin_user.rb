# frozen_string_literal: true

module AuthenticableAdminUser
  extend ActiveSupport::Concern

  private

  def ready?(**args)
    raise unauthorized_error unless context[:current_user]
    raise unauthorized_error unless context[:current_user].cs_admin?
    raise unauthorized_error unless context[:current_user].email.end_with?("@getlago.com")

    super
  end

  def current_user
    context[:current_user]
  end

  def unauthorized_error
    GraphQL::ExecutionError.new("unauthorized", extensions: {status: :unauthorized, code: "unauthorized"})
  end
end
