# frozen_string_literal: true

module Types
  class BaseArgument < GraphQL::Schema::Argument
    attr_reader :permissions

    def initialize(*args, permission: nil, **kwargs, &block)
      @permissions = [permission].compact
      super(*args, **kwargs, &block)
    end
  end
end
