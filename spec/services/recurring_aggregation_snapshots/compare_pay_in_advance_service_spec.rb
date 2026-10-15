# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::ComparePayInAdvanceService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:started_at) { Time.zone.parse("2022-03-01") }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at:, subscription_at: started_at) }
  let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "value") }
  let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, properties: {amount: "1"}) }
  let(:snapshot_units) { 5 }

  before do
    charge

    create_event(timestamp: Time.zone.parse("2022-04-10"), value: 5)
    create_event(timestamp: Time.zone.parse("2022-05-10"), value: 3)
    create(
      :recurring_aggregation_snapshot,
      organization:,
      subscription:,
      charge:,
      to_datetime: Time.zone.parse("2022-04-30").end_of_day,
      watermark: Time.zone.parse("2022-05-01"),
      units: snapshot_units,
      events_count: 1
    )

    travel_to(Time.zone.parse("2022-05-15"))
    stub_const("#{described_class}::RECHECK_DELAY", 0)
  end

  def create_event(timestamp:, value:)
    create(
      :event,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      timestamp:,
      created_at: timestamp,
      properties: {value:}
    )
  end

  it "replays the events of the period on both paths and reports no difference when the snapshot is right" do
    expect(result).to be_success
    expect(result.compared_charges_count).to eq(1)
    expect(result.compared_events_count).to eq(1)
    expect(result.rechecked).to be(false)
    expect(result.differences).to be_empty
    expect(result.rows.sole).to have_attributes(
      event_timestamp: Time.zone.parse("2022-05-10"),
      charge_id: charge.id,
      charge_filter_id: nil,
      grouped_by: {},
      snapshot_read: true,
      snapshot: have_attributes(aggregation: 8, pay_in_advance_aggregation: 3),
      full_scan: have_attributes(aggregation: 8, pay_in_advance_aggregation: 3)
    )
  end

  it "persists nothing and leaves the read gate untouched" do
    expect { result }.not_to change { [Fee.count, CachedAggregation.count, RecurringAggregationSnapshot.count] }
    expect(RecurringAggregationSnapshots.read_enabled?).to be(true)
  end

  context "when the snapshot disagrees with the full history" do
    let(:snapshot_units) { 20 }

    it "reports the event after checking it again" do
      expect(result.rechecked).to be(true)
      expect(result.differences.sole).to have_attributes(
        snapshot: have_attributes(aggregation: 23),
        full_scan: have_attributes(aggregation: 8)
      )
    end
  end

  context "when the snapshot holds another group" do
    let(:charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:, properties: {amount: "1", pricing_group_keys: ["region"]})
    end
    let(:snapshot_units) { 20 }

    before { RecurringAggregationSnapshot.update_all(grouped_by: {region: "us"}, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations

    it "does not count it as read from a snapshot nor report its difference" do
      expect(result.rows.sole).to have_attributes(snapshot_read: false)
      expect(result.differences).to be_empty
    end
  end

  context "with the ClickHouse events store", clickhouse: true do
    let(:organization) { create(:organization, clickhouse_events_store: true) }
    let(:raw_event) do
      create(
        :clickhouse_events_raw,
        organization:,
        subscription:,
        billable_metric:,
        timestamp: Time.zone.parse("2022-05-12"),
        ingested_at: Time.zone.parse("2022-05-12"),
        properties: {value: "4"}
      )
    end

    before { raw_event }

    it "replays the latest raw events of the period" do
      expect(result.compared_events_count).to eq(1)
      expect(result.rows.sole).to have_attributes(event_transaction_id: raw_event.transaction_id, snapshot_read: true)
    end

    context "when the event was inserted twice" do
      before { create(:clickhouse_events_raw, raw_event.attributes.symbolize_keys.merge(ingested_at: Time.zone.parse("2022-05-13"))) }

      it "replays it once" do
        expect(result.compared_events_count).to eq(1)
      end
    end
  end

  context "with a charge that is not paid in advance" do
    let(:charge) { create(:standard_charge, plan:, billable_metric:) }

    it "compares nothing" do
      expect(result.compared_charges_count).to eq(0)
      expect(result.compared_events_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end
end
