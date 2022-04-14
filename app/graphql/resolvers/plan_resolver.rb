# frozen_string_literal: true

module Resolvers
  class PlanResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single plan of an organization'

    argument :id, ID, required: true, description: 'Uniq ID of the plan'

    type Types::Plans::SingleObject, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.plans.find_by(id: id)
    end
  end
end
