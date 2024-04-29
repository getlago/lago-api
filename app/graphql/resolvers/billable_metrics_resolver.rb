# frozen_string_literal: true

module Resolvers
  class BillableMetricsResolver < Resolvers::BaseResolver
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

    def resolve(**args)
      result = ::BillableMetricsQuery.new(organization: current_organization).call(
        search_term: args[:search_term],
        page: args[:page],
        limit: args[:limit],
        filters: args.slice(:ids, :recurring, :aggregation_types),
      )

      result.billable_metrics
    end
  end
end
