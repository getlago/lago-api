# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  class BaseArgument < GraphQL::Schema::Argument
    attr_reader :permissions

    def initialize(*, permission: nil, permissions: nil, **, &)
      @permissions = if permission
        [permission].compact
      elsif permissions
        Array.wrap(permissions).compact
      end

      super(*, **, &)
    end
  end
end
