# frozen_string_literal: true

module Resolvers
  class EventsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query events of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::Events::Object.collection_type, null: true

    def resolve(page: nil, limit: nil)
      validate_organization!

      Event.where(organization_id: current_organization.id)
        .order(timestamp: :desc)
        .page(page)
        .per(limit)
    end
  end
end
