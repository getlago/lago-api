# frozen_string_literal: true

require 'current_context'

module RequiredOrganization
  extend ActiveSupport::Concern

  def current_organization
    context[:current_organization]
  end

  def validate_organization!
    raise organization_error('Missing organization id') unless current_organization
    raise organization_error('Not in organization') unless organization_member?

    ::CurrentContext.organization_id = current_organization.id
    ::CurrentContext.membership_id = context[:current_user]&.id

    true
  end

  def organization_error(message)
    GraphQL::ExecutionError.new(message, extensions: { status: :forbidden, code: 'forbidden' })
  end

  def organization_member?
    return false unless context[:current_user]
    return false unless current_organization

    context[:current_user].organizations.exists?(id: current_organization.id)
  end
end
