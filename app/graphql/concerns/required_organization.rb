# frozen_string_literal: true

module RequiredOrganization
  extend ActiveSupport::Concern

  def self.included(base)
    base.prepend(Module.new do
      if base.method_defined?(:resolve)
        define_method :resolve do |*args, **kwargs, &block|
          validate_organization!
          super(*args, **kwargs, &block)
        end
      end
    end)
  end
    
  private

  def current_organization
    context[:current_organization]
  end

  def validate_organization!
    raise organization_error('Missing organization id') unless current_organization
    raise organization_error('Not in organization') unless organization_member?

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
