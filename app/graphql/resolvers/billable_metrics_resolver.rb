# frozen_string_literal: true

module Resolvers
  class BillableMetricsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query billable metrics of an organization'

    argument :ids, Integer, required: false
    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::BillableMetrics::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil)
      validate_organization!

      metrics = current_organization
        .billable_metrics
        .page(page)
        .per(limit)

      metrics = metrics.where(ids: ids) if ids.present?

      metrics
    end
  end
end
