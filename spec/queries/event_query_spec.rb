# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventQuery, transaction: false do
  subject(:result) { described_class.call(organization:, filters:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:filters) { {transaction_id: event.transaction_id} }

  let(:event) do
    create(
      :event,
      code: billable_metric.code,
      organization:,
      external_subscription_id: subscription.external_id,
      timestamp: 2.days.ago
    )
  end

  before { event }

  it "returns the event" do
    expect(result).to be_success
    expect(result.event).to eq(event)
  end

  context "when the transaction id is missing" do
    let(:filters) { {transaction_id: nil} }

    it "fails validation" do
      expect(result).not_to be_success
      expect(result.error.messages[:transaction_id]).to eq(["value_is_mandatory"])
    end
  end

  context "when the transaction id belongs to another organization" do
    let(:filters) { {transaction_id: event.transaction_id} }
    let(:organization) { create(:organization) }
    let(:event) { create(:event, code: "foo", organization: create(:organization), timestamp: 2.days.ago) }

    it "returns nothing" do
      expect(result).to be_success
      expect(result.event).to be_nil
    end
  end

  context "when two subscriptions share the transaction id" do
    let(:other_subscription) { create(:subscription, customer:, plan:, external_id: "other_sub") }

    let(:other_event) do
      create(
        :event,
        code: billable_metric.code,
        organization:,
        external_subscription_id: other_subscription.external_id,
        transaction_id: event.transaction_id,
        timestamp: 2.days.ago
      )
    end

    let(:filters) do
      {transaction_id: event.transaction_id, external_subscription_id: other_subscription.external_id}
    end

    before { other_event }

    it "returns the one on the requested subscription" do
      expect(result.event).to eq(other_event)
    end
  end

  context "with clickhouse", clickhouse: true do
    let(:organization) { create(:organization, clickhouse_events_store: true) }
    let(:base_timestamp) { Time.zone.parse("2026-08-01 10:00:00.123") }

    let(:event) do
      Clickhouse::EventsRaw.create!(
        transaction_id: "tx_ms",
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: base_timestamp,
        properties: {},
        ingested_at: base_timestamp
      )
    end

    let(:sibling_event) do
      Clickhouse::EventsRaw.create!(
        transaction_id: "tx_ms",
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: base_timestamp + 0.456,
        properties: {},
        ingested_at: base_timestamp
      )
    end

    before { sibling_event }

    # The two rows are 456ms apart: a whole-second comparison matches both, so this is what
    # pins the DateTime64(3) precision of the filter.
    it "separates two events that differ only by milliseconds" do
      [event, sibling_event].each do |expected|
        query = described_class.call(
          organization:,
          filters: {
            transaction_id: "tx_ms",
            external_subscription_id: subscription.external_id,
            code: billable_metric.code,
            timestamp: expected.timestamp
          }
        )

        expect(query.event.timestamp).to eq(expected.timestamp)
      end
    end

    it "ignores the timestamp filter on the postgres store" do
      organization.update!(clickhouse_events_store: false)
      pg_event = create(
        :event,
        code: billable_metric.code,
        organization:,
        external_subscription_id: subscription.external_id,
        timestamp: 2.days.ago
      )

      query = described_class.call(
        organization:,
        filters: {transaction_id: pg_event.transaction_id, timestamp: 10.years.ago}
      )

      expect(query.event).to eq(pg_event)
    end
  end
end
