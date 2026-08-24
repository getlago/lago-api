# frozen_string_literal: true

module Resolvers
  class EventResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query a single event of an organization"

    argument :code, String, required: false, description: "Billable metric code of the event"
    argument :external_subscription_id, ID, required: false, description: "External subscription ID of the event"
    argument :timestamp_ms, GraphQL::Types::BigInt, required: false, description: "Event timestamp in milliseconds since epoch"
    argument :transaction_id, ID, required: false, description: "Transaction ID of the event"

    type Types::Events::Object, null: true

    def resolve(transaction_id: nil, external_subscription_id: nil, timestamp_ms: nil, code: nil)
      # The other arguments only ever narrow the lookup. Without this, a caller that sends
      # just an external_subscription_id would get that subscription's most recent event
      # back — a plausible-looking wrong answer instead of an error.
      if transaction_id.blank?
        return validation_error(messages: {transaction_id: ["value_is_mandatory"]})
      end

      event = if current_organization.clickhouse_events_store?
        clickhouse_event(transaction_id:, external_subscription_id:, timestamp_ms:, code:)
      else
        # NOTE: index_unique_transaction_id makes (organization_id, external_subscription_id,
        # transaction_id) unique, so the timestamp adds nothing here — and matching it in
        # milliseconds could not represent the column's microsecond precision anyway.
        postgres_event(transaction_id:, external_subscription_id:)
      end

      event || not_found_error(resource: "event")
    end

    private

    # The arguments mirror the key EventsResolver deduplicates the list on, so that every row
    # the list can show is a row this lookup can address. `code` included: two rows differing
    # only by it are separate events, both listed, and nothing else here separates them.
    def clickhouse_event(transaction_id:, external_subscription_id:, timestamp_ms:, code:)
      scope = Clickhouse::EventsRaw.where(organization_id: current_organization.id, transaction_id:)
      scope = scope.where(external_subscription_id:) if external_subscription_id.present?
      scope = scope.where(code:) if code.present?
      # NOTE: timestamp is a DateTime64(3); comparing it against a formatted string
      # silently matches nothing, so go through the millisecond representation.
      scope = scope.where("toUnixTimestamp64Milli(timestamp) = ?", timestamp_ms) if timestamp_ms.present?

      scope.order(ingested_at: :desc).first
    end

    def postgres_event(transaction_id:, external_subscription_id:)
      scope = Event.where(organization_id: current_organization.id, transaction_id:)
      scope = scope.where(external_subscription_id:) if external_subscription_id.present?

      scope.order(created_at: :desc).first
    end
  end
end
