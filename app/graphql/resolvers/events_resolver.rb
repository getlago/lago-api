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
        deduplicated_clickhouse_events
          .order(ingested_at: :desc)
          .page(page)
          .per((limit >= MAX_LIMIT) ? MAX_LIMIT : limit)
      else
        current_organization.events
          .order(created_at: :desc)
          .page(page)
          .per((limit >= MAX_LIMIT) ? MAX_LIMIT : limit)
      end
    end

    private

    # events_raw is a plain MergeTree: nothing prevents the same event from being stored
    # several times, and a batch ingestion that omits the timestamp gives every event in
    # the call the same one, so a repeated transaction_id lands as identical rows.
    # Collapse them, keeping the most recently ingested row. The Postgres store needs none
    # of this: index_unique_transaction_id makes the duplicate impossible there.
    #
    # The key includes `code` on top of the aggregation stores' own `LIMIT 1 BY
    # transaction_id, timestamp`, because those run once per billable metric and so are
    # already scoped to a single code. Here the scope is the whole organization: without
    # `code` two events that are billed separately would be shown as one.
    #
    # LIMIT 1 BY has to live in a subquery: generated at the same level as Kaminari's
    # LIMIT/OFFSET the two do not compose, and both the page and the total count come out wrong.
    def deduplicated_clickhouse_events
      base_sql = Clickhouse::EventsRaw
        .where(organization_id: current_organization.id)
        .to_sql

      deduplicated_sql = "#{base_sql} ORDER BY ingested_at DESC " \
                         "LIMIT 1 BY external_subscription_id, transaction_id, timestamp, code"

      Clickhouse::EventsRaw.from("(#{deduplicated_sql}) AS events_raw")
    end
  end
end
