# frozen_string_literal: true

module Resolvers
  class BillableMetricResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single billable metric of an organization'

    argument :id, ID, required: true, description: 'Uniq ID of the billable metric'

    type Types::BillableMetrics::SingleObject, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.billable_metrics.find_by(id: id)
    end
  end
end
