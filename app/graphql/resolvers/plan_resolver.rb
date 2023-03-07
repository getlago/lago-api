# frozen_string_literal: true

module Resolvers
  class PlanResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single plan of an organization'

    argument :id, ID, required: true, description: 'Uniq ID of the plan'

    type Types::Plans::Object, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.plans.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'plan')
    end
  end
end
