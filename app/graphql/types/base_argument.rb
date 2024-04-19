# frozen_string_literal: true

module Types
  class BaseArgument < GraphQL::Schema::Argument
    attr_reader :permission

    def initialize(*args, permission: nil, **kwargs, &block)
      @permission = permission
      super(*args, **kwargs, &block)
    end

    # NOTE: This is how you return an error instead of ignoring the field
    #       We need to decide if we prefer to fail and return an error or ignore the field
    #
    # def authorized?(obj, value, ctx)
    #   if permission && !ctx.dig(:permissions, permission)
    #     raise GraphQL::ExecutionError.new(
    #       'You are not authorized to perform this action',
    #       extensions: { status: :forbidden, code: 'forbidden' },
    #     )
    #   end
    #
    #   super
    # end
  end
end
