# frozen_string_literal: true

module Resolvers
  class BillableMetricsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query billable metrics of an organization'

    argument :ids, [String], required: false, description: 'List of plan ID to fetch'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :search_term, String, required: false

    type Types::BillableMetrics::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, search_term: nil)
      validate_organization!

      query = ::BillableMetricQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        filters: {
          ids:,
        },
      )

      result.billable_metrics
    end
  end
end
