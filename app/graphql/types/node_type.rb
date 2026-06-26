# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module NodeType
    include Types::BaseInterface
    # Add the `id` field
    include GraphQL::Types::Relay::NodeBehaviors
  end
end
