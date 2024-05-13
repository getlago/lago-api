# frozen_string_literal: true

module RequiredOrganization
  extend ActiveSupport::Concern

  private

  def ready?(**args)
    raise organization_error('Missing organization id') unless current_organization
    raise organization_error('Not in organization') unless organization_member?

    super
  end

  def current_organization
    context[:current_organization]
  end

  def organization_error(message)
    GraphQL::ExecutionError.new(message, extensions: {status: :forbidden, code: 'forbidden'})
  end

  def organization_member?
    return false unless context[:current_user]
    return false unless current_organization

    context[:current_user].organizations.exists?(id: current_organization.id)
  end
end
