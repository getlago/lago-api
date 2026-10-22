# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::CompareUsageService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:started_at) { Time.zone.parse("2022-03-01") }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at:, subscription_at: started_at) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true, field_name: "value") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}) }
  let(:snapshot_units) { 5 }
  let(:snapshot_to_datetime) { Time.zone.parse("2022-04-30").end_of_day }

  before do
    charge

    create_event(timestamp: Time.zone.parse("2022-04-10"), value: 5)
    create_event(timestamp: Time.zone.parse("2022-05-10"), value: 3)
    create(
      :recurring_aggregation_snapshot,
      organization:,
      subscription:,
      charge:,
      to_datetime: snapshot_to_datetime,
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

  it "computes both paths and reports no difference when the snapshot is right" do
    expect(result).to be_success
    expect(result.compared_charges_count).to eq(1)
    expect(result.snapshot_charges_count).to eq(1)
    expect(result.rechecked).to be(false)
    expect(result.differences).to be_empty
    expect(result.rows.sole).to have_attributes(
      charge_id: charge.id,
      billable_metric_code: billable_metric.code,
      charge_filter_id: nil,
      grouped_by: {},
      snapshot_read: true,
      snapshot: have_attributes(units: 8, events_count: 2, amount_cents: 800),
      full_scan: have_attributes(units: 8, events_count: 2, amount_cents: 800)
    )
  end

  it "leaves the read gate and the organization untouched" do
    result

    expect(RecurringAggregationSnapshots.read_enabled?(organization)).to be(false)
    expect(RecurringAggregationSnapshot.count).to eq(1)
  end

  context "when the snapshot disagrees with the full history" do
    let(:snapshot_units) { 20 }

    it "reports the leaf after checking it again" do
      expect(result.rechecked).to be(true)
      expect(result.differences.sole).to have_attributes(
        charge_id: charge.id,
        snapshot: have_attributes(units: 23),
        full_scan: have_attributes(units: 8)
      )
    end
  end

  context "when the aggregation would not start from the snapshot" do
    let(:billable_metric) { create(:weighted_sum_billable_metric, organization:, recurring: true, field_name: "value") }
    let(:snapshot_to_datetime) { Time.zone.parse("2022-03-31").end_of_day }
    let(:snapshot_units) { 20 }

    it "does not count it as read from a snapshot nor report its difference" do
      expect(result.snapshot_charges_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end

  context "with a charge filter" do
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
    let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "1"}) }

    before do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
    end

    it "compares the default bucket read from its snapshot and leaves the filter without one out" do
      expect(result.snapshot_charges_count).to eq(1)
      expect(result.rows.find { it.charge_filter_id.nil? }).to have_attributes(snapshot_read: true)
      expect(result.rows.find { it.charge_filter_id == charge_filter.id }).to have_attributes(snapshot_read: false)
      expect(result.differences).to be_empty
    end

    context "when the filter had no usage at the end of the previous period" do
      let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "1"}, created_at: Time.zone.parse("2022-04-01")) }

      it "counts the filter as read from the period" do
        expect(result.snapshot_charges_count).to eq(1)
        expect(result.rows.find { it.charge_filter_id == charge_filter.id }).to have_attributes(snapshot_read: true)
        expect(result.differences).to be_empty
      end
    end
  end

  context "without a snapshot before the period" do
    before { RecurringAggregationSnapshot.delete_all }

    it "compares nothing" do
      expect(result.compared_charges_count).to eq(1)
      expect(result.snapshot_charges_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end

  context "with a non recurring billable metric" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }

    it "compares nothing" do
      expect(result.compared_charges_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end
end
