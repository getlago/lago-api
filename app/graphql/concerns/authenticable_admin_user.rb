# frozen_string_literal: true

module AuthenticableAdminUser
  extend ActiveSupport::Concern

  # NOTE: Okta and Entra ID identities come from a provider configured by a tenant, so they never
  #       grant access to the admin endpoints.
  SSO_LOGIN_METHODS = [
    Organizations::AuthenticationMethods::OKTA,
    Organizations::AuthenticationMethods::ENTRA_ID
  ].freeze

  private

  def ready?(**args)
    raise unauthorized_error unless License.premium?
    raise unauthorized_error unless context[:current_user]
    raise unauthorized_error unless context[:current_user].cs_admin?
    raise unauthorized_error unless context[:current_user].email.end_with?("@getlago.com")
    raise unauthorized_error if SSO_LOGIN_METHODS.include?(context[:login_method])

    super
  end

  def current_user
    context[:current_user]
  end

  def unauthorized_error
    GraphQL::ExecutionError.new("unauthorized", extensions: {status: :unauthorized, code: "unauthorized"})
  end
end
