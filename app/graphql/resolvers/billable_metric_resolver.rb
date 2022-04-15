# frozen_string_literal: true

module Resolvers
  class BillableMetricResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single billable metric of an organization'

    argument :id, ID, required: true, description: 'Uniq ID of the billable metric'

    type Types::BillableMetrics::SingleObject, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.billable_metrics.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error
    end
  end
end
