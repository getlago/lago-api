# frozen_string_literal: true

module Resolvers
  class SubscriptionResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single subscription of an organization'

    argument :id, ID, required: true, description: 'Uniq ID of the subscription'

    type Types::Subscriptions::Object, null: true

    def resolve(id: nil)
      current_organization.subscriptions.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'subscription')
    end
  end
end
