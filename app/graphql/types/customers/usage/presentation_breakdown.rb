# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Customers
    module Usage
      class PresentationBreakdown < Types::BaseObject
        graphql_name "PresentationBreakdownUsage"

        field :presentation_by, GraphQL::Types::JSON, null: false
        field :units, GraphQL::Types::String, null: false
      end
    end
  end
end
