# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::CountDuplicateEventsService, clickhouse: {clean_before: true} do
  subject(:count) { described_class.call(subscription:, codes:, from_datetime:, to_datetime:) }

  let(:organization) { create(:organization, clickhouse_events_store: true) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:codes) { [billable_metric.code] }
  let(:from_datetime) { Time.current.beginning_of_day }
  let(:to_datetime) { from_datetime + 1.day }

  def create_event(timestamp: from_datetime + 1.hour, transaction_id: "tr_1", code: billable_metric.code)
    create(
      :clickhouse_events_raw,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code:,
      timestamp:,
      transaction_id:
    )
  end

  it "counts the events the subscription sent twice under the same transaction id" do
    create_event(transaction_id: "tr_1")
    create_event(transaction_id: "tr_1")
    create_event(transaction_id: "tr_2")

    expect(count.events_count).to eq(3)
    expect(count.duplicates_count).to eq(1)
    expect(count.duplicates_by_code).to eq({billable_metric.code => 1})
  end

  it "survives the merge that collapses the re-sent rows of the enriched table" do
    create_event(transaction_id: "tr_1")
    create_event(transaction_id: "tr_1")
    Clickhouse::EventsRaw.connection.execute("OPTIMIZE TABLE events_enriched FINAL")

    expect(count.duplicates_count).to eq(1)
  end

  it "reports no duplicate when every transaction id is unique" do
    create_event(transaction_id: "tr_1")
    create_event(transaction_id: "tr_2")

    expect(count.events_count).to eq(2)
    expect(count.duplicates_count).to eq(0)
  end

  context "with several metrics in the window" do
    let(:other_billable_metric) { create(:sum_billable_metric, organization:) }
    let(:codes) { [billable_metric.code, other_billable_metric.code] }

    it "reports the duplicates of each metric on its own code" do
      create_event(transaction_id: "tr_1")
      create_event(transaction_id: "tr_1")
      create_event(transaction_id: "tr_2", code: other_billable_metric.code)

      expect(count.duplicates_count).to eq(1)
      expect(count.duplicates_by_code).to eq({billable_metric.code => 1, other_billable_metric.code => 0})
    end
  end

  it "ignores the events of another metric and the ones outside the window" do
    create_event(transaction_id: "tr_1")
    create_event(transaction_id: "tr_2", code: "other_code")
    create_event(transaction_id: "tr_3", timestamp: to_datetime + 1.hour)

    expect(count.events_count).to eq(1)
    expect(count.duplicates_count).to eq(0)
  end
end
