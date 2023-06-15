# frozen_string_literal: true

module Resolvers
  class BillableMetricsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query billable metrics of an organization'

    argument :ids, [String], required: false, description: 'List of plan ID to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :recurring, Boolean, required: false
    argument :search_term, String, required: false

    argument :aggregation_types, [Types::BillableMetrics::AggregationTypeEnum], required: false

    type Types::BillableMetrics::Object.collection_type, null: false

    def resolve( # rubocop:disable Metrics/ParameterLists
      ids: nil,
      page: nil,
      limit: nil,
      search_term: nil,
      aggregation_types: nil,
      recurring: nil
    )
      validate_organization!

      query = ::BillableMetricsQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        filters: {
          ids:,
          recurring:,
          aggregation_types:,
        },
      )

      result.billable_metrics
    end
  end
end
