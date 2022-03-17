# frozen_string_literal: true

module Resolvers
  class BillableMetricsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    type [Types::BillableMetrics::BillableMetricObject], null: false

    def resolve
      current_organization.billable_metrics
    end
  end
end
