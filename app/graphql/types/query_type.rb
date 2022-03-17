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
      Types::BillableMetrics::BillableMetricObject.connection_type,
      resolver: Resolvers::BillableMetricsResolver
    ) do
      description 'Query billable metrics of an organization'
    end
  end
end
