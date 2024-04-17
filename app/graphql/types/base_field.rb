# frozen_string_literal: true

module Types
  class BaseField < GraphQL::Schema::Field
    argument_class Types::BaseArgument

    attr_reader :permission

    def initialize(*args, permission: nil, **kwargs, &block)
      @permission = permission.to_s if permission

      if @permission
        kwargs[:null] = true
      end

      super(*args, **kwargs, &block)

      extension(Extensions::FieldAuthorizationExtension) if @permission
    end

    # def authorized?(object, args, context)
    #   return false if permission
    #
    #   super
    # end
  end
end
