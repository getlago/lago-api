# frozen_string_literal: true

module Resolvers
  class EventResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query a single event of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the event"

    type Types::Events::Object, null: true

    def resolve(id: nil)
      if current_organization.clickhouse_events_store?
        Clickhouse::EventsRaw.where(organization_id: current_organization.id).find(id)
      else
        Event.where(organization_id: current_organization.id).find(id)
      end
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "event")
    end
  end
end
