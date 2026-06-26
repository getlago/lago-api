# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Extensions
  class FieldAuthorizationExtension < GraphQL::Schema::FieldExtension
    def resolve(object:, arguments:, context:)
      super if field.permissions.any? { |p| context.dig(:permissions, p) }
    end
  end
end
