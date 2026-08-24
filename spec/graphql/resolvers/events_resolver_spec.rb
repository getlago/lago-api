# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::EventsResolver, clickhouse: true, transaction: false do
  let(:query) do
    <<~GQL
      query($page: Int) {
        events(page: $page, limit: 5) {
          collection {
            id
            code
            transactionId
            externalSubscriptionId
            timestamp
            receivedAt
            customerTimezone
            ipAddress
            apiClient
            payload
            billableMetricName
            matchBillableMetric
            matchCustomField
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:organization) { create(:organization) }
  let(:user) { create(:user) }
  let(:membership) { create(:membership, user:, organization:) }
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

  before do
    event
    membership
  end

  it "returns a list of events" do
    result = execute_graphql(
      current_user: user,
      current_organization: organization,
      query:
    )

    events_response = result["data"]["events"]

    expect(events_response["collection"].count).to eq(Event.where(organization_id: organization.id).count)
    expect(events_response["collection"].first["id"]).to eq(event.id)
    expect(events_response["collection"].first["code"]).to eq(event.code)
    expect(events_response["collection"].first["externalSubscriptionId"]).to eq(subscription.external_id)
    expect(events_response["collection"].first["transactionId"]).to eq(event.transaction_id)
    expect(events_response["collection"].first["timestamp"]).to eq(event.timestamp.iso8601)
    expect(events_response["collection"].first["receivedAt"]).to eq(event.created_at.iso8601)
    expect(events_response["collection"].first["customerTimezone"]).to eq("TZ_UTC")
    expect(events_response["collection"].first["ipAddress"]).to eq(event.metadata["ip_address"])
    expect(events_response["collection"].first["apiClient"]).to eq(event.metadata["user_agent"])
    expect(events_response["collection"].first["payload"]).to be_present
    expect(events_response["collection"].first["billableMetricName"]).to eq(billable_metric.name)
    expect(events_response["collection"].first["matchBillableMetric"]).to be_truthy
    expect(events_response["collection"].first["matchCustomField"]).to be_truthy
  end

  context "with a deleted billable metric" do
    it "does not return duplicated events" do
      billable_metric.discard!
      create(:billable_metric, organization:, code: billable_metric.code)

      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:
      )

      events_response = result["data"]["events"]

      expect(events_response["collection"].count).to eq(Event.where(organization_id: organization.id).count)
      expect(events_response["collection"].first["id"]).to eq(event.id)
    end
  end

  context "with missing billable_metric" do
    let(:event) do
      create(
        :event,
        code: "foo",
        organization:,
        timestamp: 2.days.ago,
        properties: {foo_bar: 1234}
      )
    end

    it "returns a list of events" do
      event
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:
      )

      events_response = result["data"]["events"]
      expect(events_response["collection"].first["matchBillableMetric"]).to be_falsey
    end
  end

  context "with missing custom field" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "mandatory") }

    it "returns a list of events" do
      event
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:
      )

      events_response = result["data"]["events"]
      expect(events_response["collection"].first["matchCustomField"]).to be_falsey
    end
  end

  context "with clickhouse event store" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    let(:event) do
      Clickhouse::EventsRaw.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: 2.days.ago,
        properties: {},
        precise_total_amount_cents: 12,
        ingested_at: 2.days.ago
      )
    end

    it "returns a list of events" do
      result = execute_graphql(
        current_user: user,
        current_organization: organization,
        query:
      )

      events_response = result["data"]["events"]

      expect(events_response["collection"].count).to eq(Clickhouse::EventsRaw.where(organization_id: organization.id).count)
      expect(events_response["collection"].first["id"]).to eq(event.id)
      expect(events_response["collection"].first["code"]).to eq(event.code)
      expect(events_response["collection"].first["externalSubscriptionId"]).to eq(subscription.external_id)
      expect(events_response["collection"].first["transactionId"]).to eq(event.transaction_id)
      expect(events_response["collection"].first["timestamp"]).to eq(event.timestamp.iso8601)
      expect(events_response["collection"].first["receivedAt"]).to eq(event.created_at.iso8601)
      expect(events_response["collection"].first["customerTimezone"]).to eq("TZ_UTC")
      expect(events_response["collection"].first["ipAddress"]).to be_nil
      expect(events_response["collection"].first["apiClient"]).to be_nil
      expect(events_response["collection"].first["payload"]).to be_present
      expect(events_response["collection"].first["billableMetricName"]).to eq(billable_metric.name)
      expect(events_response["collection"].first["matchBillableMetric"]).to be_truthy
      expect(events_response["collection"].first["matchCustomField"]).to be_truthy
    end

    context "when querying an empty page" do
      it "returns an empty list of events" do
        result = execute_graphql(
          current_user: user,
          current_organization: organization,
          query:,
          variables: {page: 5}
        )

        events_response = result["data"]["events"]
        expect(events_response["collection"].count).to be_zero
      end
    end

    context "when the same event was ingested several times" do
      let(:event_timestamp) { 2.days.ago.change(usec: 0) }

      let(:event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_duplicated",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: event_timestamp,
          properties: {},
          ingested_at: event_timestamp
        )
      end

      let(:later_duplicate) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_duplicated",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: event_timestamp,
          properties: {},
          ingested_at: event_timestamp + 1.second
        )
      end

      before { later_duplicate }

      it "returns the event once, keeping the most recently ingested row" do
        expect(Clickhouse::EventsRaw.where(organization_id: organization.id).count).to eq(2)

        result = execute_graphql(
          current_user: user,
          current_organization: organization,
          query:
        )

        events_response = result["data"]["events"]

        expect(events_response["collection"].count).to eq(1)
        expect(events_response["metadata"]["totalCount"]).to eq(1)
        expect(events_response["collection"].first["transactionId"]).to eq("tx_duplicated")
        expect(events_response["collection"].first["id"]).to eq(later_duplicate.id)
      end
    end

    context "when the same transaction id is reused across two billable metrics" do
      let(:event_timestamp) { 2.days.ago.change(usec: 0) }
      let(:other_billable_metric) { create(:billable_metric, organization:, code: "other_bm") }

      let(:event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_shared_code",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: event_timestamp,
          properties: {},
          ingested_at: event_timestamp
        )
      end

      let(:event_on_other_metric) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_shared_code",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: other_billable_metric.code,
          timestamp: event_timestamp,
          properties: {},
          ingested_at: event_timestamp
        )
      end

      before { event_on_other_metric }

      it "keeps both — the aggregation stores bill them separately, one per code" do
        result = execute_graphql(
          current_user: user,
          current_organization: organization,
          query:
        )

        events_response = result["data"]["events"]

        expect(events_response["collection"].count).to eq(2)
        expect(events_response["metadata"]["totalCount"]).to eq(2)
        expect(events_response["collection"].map { it["code"] })
          .to match_array([billable_metric.code, other_billable_metric.code])
      end
    end

    context "when the same transaction id is used on two subscriptions" do
      let(:event_timestamp) { 2.days.ago.change(usec: 0) }
      let(:other_subscription) { create(:subscription, customer:, plan:, external_id: "other_sub") }

      let(:event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_shared",
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: event_timestamp,
          properties: {},
          ingested_at: event_timestamp
        )
      end

      let(:event_on_other_subscription) do
        Clickhouse::EventsRaw.create!(
          transaction_id: "tx_shared",
          organization_id: organization.id,
          external_subscription_id: other_subscription.external_id,
          code: billable_metric.code,
          timestamp: event_timestamp,
          properties: {},
          ingested_at: event_timestamp
        )
      end

      before { event_on_other_subscription }

      it "keeps both, they are distinct events" do
        result = execute_graphql(
          current_user: user,
          current_organization: organization,
          query:
        )

        events_response = result["data"]["events"]

        expect(events_response["collection"].count).to eq(2)
        expect(events_response["metadata"]["totalCount"]).to eq(2)
        expect(events_response["collection"].map { it["externalSubscriptionId"] })
          .to match_array([subscription.external_id, other_subscription.external_id])
      end
    end
  end
end
