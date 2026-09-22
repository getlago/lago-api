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

  def create_event(timestamp: from_datetime + 1.hour, transaction_id: "tr_1", value: "10.0", code: billable_metric.code)
    create(
      :clickhouse_events_enriched,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code:,
      timestamp:,
      transaction_id:,
      value:,
      decimal_value: value.to_d
    )
  end

  it "counts the rows the events store collapses at read time" do
    create_event(transaction_id: "tr_1", value: "10.0")
    create_event(transaction_id: "tr_1", value: "12.0")
    create_event(transaction_id: "tr_2")

    expect(count.events_count).to eq(3)
    expect(count.duplicates_count).to eq(1)
  end

  it "reports no duplicate when every transaction id is unique" do
    create_event(transaction_id: "tr_1")
    create_event(transaction_id: "tr_2")

    expect(count.events_count).to eq(2)
    expect(count.duplicates_count).to eq(0)
  end

  it "ignores the events of another metric and the ones outside the window" do
    create_event(transaction_id: "tr_1")
    create_event(transaction_id: "tr_2", code: "other_code")
    create_event(transaction_id: "tr_3", timestamp: to_datetime + 1.hour)

    expect(count.events_count).to eq(1)
    expect(count.duplicates_count).to eq(0)
  end
end
