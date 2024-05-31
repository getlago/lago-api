# frozen_string_literal: true

module Types
  class BaseArgument < GraphQL::Schema::Argument
    attr_reader :permissions

    def initialize(*args, permission: nil, permissions: nil, **kwargs, &block)
      @permissions = if permission
        [permission].compact
      elsif permissions
        Array.wrap(permissions).compact
      end

      super(*args, **kwargs, &block)
    end
  end
end
