# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Resolvers
  class BaseResolver < GraphQL::Schema::Resolver
    include ExecutionErrorResponder
    include CanRequirePermissions
  end
end
