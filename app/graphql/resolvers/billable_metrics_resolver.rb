# frozen_string_literal: true

module Resolvers
  class BillableMetricsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    type Types::BillableMetrics::BillableMetricObject.collection_type, null: false

    def resolve(page: nil, limit: nil)
      current_organization
        .billable_metrics
        .page(page)
        .per(limit)
    end
  end
end
