# frozen_string_literal: true

module Resolvers
  class EventsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    MAX_LIMIT = 1000

    description "Query events of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :source, String, required: false, description: "Filter events by source (usage, fixed_charge, or nil for all)"

    type Types::Events::Object.collection_type, null: true

    def resolve(page: nil, limit: nil, source: nil)
      base_query = if current_organization.clickhouse_events_store?
        Clickhouse::EventsRaw.where(organization_id: current_organization.id)
      else
        Event.where(organization_id: current_organization.id)
      end

      # Apply source filtering if specified
      base_query = base_query.where(source:) if source.present?

      if current_organization.clickhouse_events_store?
        base_query
          .order(ingested_at: :desc)
          .page(page)
          .per((limit >= MAX_LIMIT) ? MAX_LIMIT : limit)
      else
        base_query
          .order(created_at: :desc)
          .page(page)
          .per((limit >= MAX_LIMIT) ? MAX_LIMIT : limit)
      end
    end
  end
end
