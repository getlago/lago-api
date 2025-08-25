# frozen_string_literal: true

module Resolvers
  class EventsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    MAX_LIMIT = 1000

    description "Query events of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::Events::Object.collection_type, null: true

    def resolve(page: nil, limit: nil)
      if current_organization.clickhouse_events_store?
        cte = Clickhouse::EventsRaw
          .where(organization_id: current_organization.id)
          .limit_by(1, "transaction_id, timestamp, external_subscription_id, code")
          .order(ingested_at: :desc)

        Clickhouse::EventsRaw
          .from("(#{cte.to_sql}) as events_raw")
          .page(page)
          .per((limit >= MAX_LIMIT) ? MAX_LIMIT : limit)
      else
        Event.where(organization_id: current_organization.id)
          .order(created_at: :desc)
          .page(page)
          .per((limit >= MAX_LIMIT) ? MAX_LIMIT : limit)
      end
    end
  end
end
