# frozen_string_literal: true

module CanRequirePermissions
  extend ActiveSupport::Concern

  private

  def ready?(**args)
    if defined? self.class::REQUIRED_PERMISSION
      has_permission = context.dig(:permissions, self.class::REQUIRED_PERMISSION)
      raise not_enough_permissions_error unless has_permission
    end

    super
  end

  def not_enough_permissions_error
    extensions = {
      status: :forbidden,
      code: 'forbidden',
      required_permissions: Array.wrap(self.class::REQUIRED_PERMISSION)
    }

    GraphQL::ExecutionError.new('Missing permissions', extensions:)
  end
end
