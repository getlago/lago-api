# frozen_string_literal: true

module Resolvers
  class IntegrationResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single integration'

    argument :id, ID, required: false, description: 'Uniq ID of the integration'

    type Types::Integrations::Object, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.integrations.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'integration')
    end
  end
end
