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
      query_result = EventQuery.call(
        organization: current_organization,
        filters: {
          transaction_id:,
          external_subscription_id:,
          code:,
          timestamp: timestamp_ms && Time.zone.at(Rational(timestamp_ms, 1000))
        }
      )

      return result_error(query_result) unless query_result.success?

      query_result.event || not_found_error(resource: "event")
    end
  end
end
