# frozen_string_literal: true

module Resolvers
  class BillableMetricsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query billable metrics of an organization'

    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::BillableMetrics::BillableMetricObject.collection_type, null: false

    def resolve(page: nil, limit: nil)
      current_organization
        .billable_metrics
        .page(page)
        .per(limit)
    end
  end
end
