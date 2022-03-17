# frozen_string_literal: true

module RequiredOrganization
  extend ActiveSupport::Concern

  def current_organization
    context[:current_organization]
  end

  private

  def ready?(*)
    raise missing_organization_error unless current_organization

    true
  end

  def missing_organization_error
    GraphQL::ExecutionError.new('Missing organization', extensions: { status: :forbidden, code: 'forbidden' })
  end
end
