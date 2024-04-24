# frozen_string_literal: true

module Types
  class BaseArgument < GraphQL::Schema::Argument
    attr_reader :permission

    def initialize(*args, permission: nil, **kwargs, &block)
      @permission = permission
      super(*args, **kwargs, &block)
    end
  end
end
