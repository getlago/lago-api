# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  class BaseConnection < Types::BaseObject
    # add `nodes` and `pageInfo` fields, as well as `edge_type(...)` and `node_nullable(...)` overrides
    include GraphQL::Types::Relay::ConnectionBehaviors
  end
end
