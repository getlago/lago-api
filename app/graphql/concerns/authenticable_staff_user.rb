# frozen_string_literal: true

module AuthenticableStaffUser
  extend ActiveSupport::Concern

  private

  def ready?(**args)
    admin = context[:current_admin_user]
    raise unauthorized_error if admin.blank?

    super
  end

  def current_admin_user
    context[:current_admin_user]
  end

  def unauthorized_error
    GraphQL::ExecutionError.new("unauthorized", extensions: {status: :unauthorized, code: "unauthorized"})
  end
end
