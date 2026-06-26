# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  class BaseEdge < Types::BaseObject
    # add `node` and `cursor` fields, as well as `node_type(...)` override
    include GraphQL::Types::Relay::EdgeBehaviors
  end
end
