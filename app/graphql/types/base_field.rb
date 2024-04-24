# frozen_string_literal: true

module Types
  class BaseField < GraphQL::Schema::Field
    argument_class Types::BaseArgument

    attr_reader :permissions

    def initialize(*args, permission: nil, permissions: nil, **kwargs, &block)
      if permission
        @permissions = [permission.to_s]
      elsif permissions
        @permissions = Array.wrap(permissions).map(&:to_s)
      end

      kwargs[:null] = true if @permissions

      super(*args, **kwargs, &block)

      extension(Extensions::FieldAuthorizationExtension) if @permissions
    end
  end
end
