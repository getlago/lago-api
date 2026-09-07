# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::EventResolver, transaction: false do
  let(:query) do
    <<~GQL
      query($eventTransactionId: ID!) {
        event(transactionId: $eventTransactionId) {
          id
          code
          transactionId
          externalSubscriptionId
          timestamp
          timestampMs
          receivedAt
          customerTimezone
          ipAddress
          apiClient
          payload
          billableMetricName
          matchBillableMetric
          matchCustomField
        }
      }
    GQL
  end

  # The full dedup key: what the Events tab has to send to address one specific event.
  let(:keyed_query) do
    <<~GQL
      query($transactionId: ID, $externalSubscriptionId: ID, $timestampMs: BigInt, $code: String) {
        event(
          transactionId: $transactionId
          externalSubscriptionId: $externalSubscriptionId
          timestampMs: $timestampMs
          code: $code
        ) {
          id
          code
          transactionId
          externalSubscriptionId
          timestampMs
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:event) do
    create(
      :event,
      code: billable_metric.code,
      organization:,
      external_subscription_id: subscription.external_id,
      timestamp: 2.days.ago,
      properties: {foo_bar: 1234},
      metadata: {user_agent: "Lago Ruby v0.0.1", ip_address: "182.11.32.11"}
    )
  end

  before { event }

  it "returns a single event" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {eventTransactionId: event.transaction_id}
    )

    event_response = result["data"]["event"]
    expect(event_response["id"]).to eq(event.id)
    expect(event_response["code"]).to eq(event.code)
  end

  context "with clickhouse", clickhouse: true do
    let(:event) do
      create(:clickhouse_events_raw, organization_id: organization.id)
    end

    before { organization.update!(clickhouse_events_store: true) }

    it "returns a single event" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {eventTransactionId: event.transaction_id}
      )

      event_response = result["data"]["event"]
      expect(event_response["id"]).to eq(event.id)
      expect(event_response["code"]).to eq(event.code)
    end
  end

  context "when event is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {eventTransactionId: "non_existing"}
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end

  context "when no identifying argument is given" do
    it "returns a validation error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: keyed_query,
        variables: {}
      )

      expect_graphql_error(
        result:,
        message: "Unprocessable Entity"
      )
    end
  end

  context "when only the external subscription id is given" do
    it "returns a validation error rather than the subscription's latest event" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: keyed_query,
        variables: {externalSubscriptionId: event.external_subscription_id}
      )

      expect_graphql_error(
        result:,
        message: "Unprocessable Entity"
      )
    end
  end

  context "when the identifiers contain separator characters" do
    let(:other_subscription) { create(:subscription, customer:, plan:, external_id: "sub/with-slash") }

    let(:event) do
      create(
        :event,
        code: billable_metric.code,
        organization:,
        external_subscription_id: other_subscription.external_id,
        transaction_id: "tx/with-slash-and-dash",
        timestamp: 2.days.ago
      )
    end

    it "resolves the event" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: keyed_query,
        variables: {
          transactionId: event.transaction_id,
          externalSubscriptionId: event.external_subscription_id
        }
      )

      expect(result["data"]["event"]["id"]).to eq(event.id)
    end
  end

  it "exposes the timestamp in milliseconds" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {eventTransactionId: event.transaction_id}
    )

    # BigInt goes over the wire as a string, which is what keeps it lossless for JS clients.
    expect(result["data"]["event"]["timestampMs"]).to eq((event.timestamp.to_r * 1000).round.to_s)
  end

  context "when the same transaction id is used on two subscriptions" do
    let(:other_subscription) { create(:subscription, customer:, plan:, external_id: "other_sub") }

    let(:event_on_other_subscription) do
      create(
        :event,
        code: billable_metric.code,
        organization:,
        external_subscription_id: other_subscription.external_id,
        transaction_id: event.transaction_id,
        timestamp: 2.days.ago
      )
    end

    before { event_on_other_subscription }

    it "resolves each one through its external subscription id" do
      [event, event_on_other_subscription].each do |expected|
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query: keyed_query,
          variables: {
            transactionId: expected.transaction_id,
            externalSubscriptionId: expected.external_subscription_id
          }
        )

        expect(result["data"]["event"]["id"]).to eq(expected.id)
        expect(result["data"]["event"]["externalSubscriptionId"]).to eq(expected.external_subscription_id)
      end
    end
  end

  context "with clickhouse duplicates differing only by timestamp", clickhouse: true do
    let(:first_timestamp) { 2.days.ago.change(usec: 0) }

    let(:event) do
      Clickhouse::EventsRaw.create!(
        transaction_id: "tx_same",
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: first_timestamp,
        properties: {},
        ingested_at: first_timestamp
      )
    end

    let(:later_event) do
      Clickhouse::EventsRaw.create!(
        transaction_id: "tx_same",
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: first_timestamp + 1.second,
        properties: {},
        ingested_at: first_timestamp + 1.second
      )
    end

    before do
      organization.update!(clickhouse_events_store: true)
      later_event
    end

    it "resolves deterministically to the most recently ingested row without a timestamp" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: keyed_query,
        variables: {transactionId: "tx_same", externalSubscriptionId: subscription.external_id}
      )

      expect(result["data"]["event"]["timestampMs"]).to eq((later_event.timestamp.to_r * 1000).round.to_s)
    end

    context "when the row ingested last is not the row with the latest timestamp" do
      # The two columns are inverted on purpose: ordering by `timestamp` returns the other
      # row, so the example pins which column the resolver orders on. Move them together and
      # both orderings agree, leaving the assertion unable to fail.
      let(:event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_same",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: first_timestamp,
          properties: {},
          ingested_at: first_timestamp + 1.hour
        )
      end

      let(:later_event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_same",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: first_timestamp + 1.hour,
          properties: {},
          ingested_at: first_timestamp
        )
      end

      it "resolves to the most recently ingested one" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query: keyed_query,
          variables: {transactionId: "tx_same", externalSubscriptionId: subscription.external_id}
        )

        expect(result["data"]["event"]["timestampMs"]).to eq((first_timestamp.to_r * 1000).round.to_s)
      end
    end

    context "when two rows differ only by code" do
      let(:later_event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_same",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: "other_code",
          timestamp: first_timestamp,
          properties: {},
          ingested_at: first_timestamp
        )
      end

      it "resolves each one through its code" do
        # Same transaction, subscription, timestamp AND ingestion second: the synthesized
        # Clickhouse::EventsRaw#id is identical for both, so code is the only separator left.
        expect(event.id).to eq(later_event.id)

        [event, later_event].each do |expected|
          result = execute_graphql(
            current_user: membership.user,
            current_organization: organization,
            query: keyed_query,
            variables: {
              transactionId: "tx_same",
              externalSubscriptionId: subscription.external_id,
              timestampMs: (first_timestamp.to_r * 1000).round,
              code: expected.code
            }
          )

          expect(result["data"]["event"]["code"]).to eq(expected.code)
        end
      end
    end

    context "when the identifiers contain separator characters" do
      let(:event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx/with-slash-and-dash",
          organization_id: organization.id,
          external_subscription_id: "sub/with-slash",
          code: billable_metric.code,
          timestamp: first_timestamp,
          properties: {},
          ingested_at: first_timestamp
        )
      end

      let(:later_event) { event }

      it "resolves the event despite the synthesized id being a dash-joined string" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query: keyed_query,
          variables: {
            transactionId: "tx/with-slash-and-dash",
            externalSubscriptionId: "sub/with-slash",
            timestampMs: (first_timestamp.to_r * 1000).round
          }
        )

        expect(result["data"]["event"]["id"]).to eq(event.id)
        expect(result["data"]["event"]["transactionId"]).to eq("tx/with-slash-and-dash")
        expect(result["data"]["event"]["externalSubscriptionId"]).to eq("sub/with-slash")
      end
    end

    it "resolves each one through its millisecond timestamp" do
      [event, later_event].each do |expected|
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query: keyed_query,
          variables: {
            transactionId: expected.transaction_id,
            externalSubscriptionId: expected.external_subscription_id,
            timestampMs: (expected.timestamp.to_r * 1000).round
          }
        )

        expect(result["data"]["event"]["timestampMs"]).to eq((expected.timestamp.to_r * 1000).round.to_s)
      end
    end
  end
end
