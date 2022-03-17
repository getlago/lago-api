# frozen_string_literal: true

module Types
  # QueryType
  class QueryType < Types::BaseObject
    # Add `node(id: ID!) and `nodes(ids: [ID!]!)`
    include GraphQL::Types::Relay::HasNodeField
    include GraphQL::Types::Relay::HasNodesField

    field :current_user, resolver: Resolvers::CurrentUserResolver

    field(
      :billable_metrics,
      resolver: Resolvers::BillableMetricsResolver,
      null: true
    ) do
      description 'Query billable metrics of an organization'

      argument :page, Integer, required: false
      argument :limit, Integer, required: false
    end
  end
end
