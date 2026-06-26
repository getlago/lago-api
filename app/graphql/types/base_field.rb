# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  class BaseField < GraphQL::Schema::Field
    argument_class Types::BaseArgument

    attr_reader :permissions

    def initialize(*, permission: nil, permissions: nil, **kwargs, &)
      if permission
        @permissions = [permission.to_s]
      elsif permissions
        @permissions = Array.wrap(permissions).map(&:to_s)
      end

      kwargs[:null] = true if @permissions

      super(*, **kwargs, &)

      extension(Extensions::FieldAuthorizationExtension) if @permissions
    end
  end
end
