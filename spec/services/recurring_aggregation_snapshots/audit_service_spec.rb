# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::AuditService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:started_at) { Time.zone.parse("2022-03-01") }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at:, subscription_at: started_at) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true, field_name: "value") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}) }
  let(:to_datetime) { Time.zone.parse("2022-03-31").end_of_day }
  let(:watermark) { Time.zone.parse("2022-04-01T00:10:00") }
  let(:snapshot_units) { 5 }

  before do
    charge

    create(
      :invoice_subscription,
      subscription:,
      invoice: create(:invoice, customer:, organization:),
      timestamp: to_datetime + 1.second,
      from_datetime: started_at,
      to_datetime:,
      charges_from_datetime: started_at,
      charges_to_datetime: to_datetime
    )

    create_event(timestamp: Time.zone.parse("2022-03-10"), value: 5, created_at: watermark - 1.hour)
    # Ingested after the watermark, left to the next period's snapshot
    create_event(timestamp: Time.zone.parse("2022-03-20"), value: 3, created_at: watermark + 1.minute)

    create_snapshot(units: snapshot_units, events_count: 1)

    travel_to(Time.zone.parse("2022-04-15"))
  end

  def create_event(timestamp:, value:, created_at:, region: nil)
    create(
      :event,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      timestamp:,
      created_at:,
      properties: {value:, region:}.compact
    )
  end

  def create_snapshot(**attributes)
    create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, watermark:, **attributes)
  end

  it "reports no difference when the snapshot matches its events up to the watermark" do
    expect(result).to be_success
    expect(result.audited_charges_count).to eq(1)
    expect(result.snapshot_charges_count).to eq(1)
    expect(result.charges_without_marker).to be_empty
    expect(result.charges_without_invoice).to be_empty
    expect(result.differences).to be_empty
    expect(result.rows.sole).to have_attributes(
      charge_id: charge.id,
      billable_metric_code: billable_metric.code,
      charge_filter_id: nil,
      grouped_by: {},
      to_datetime: to_datetime.floor(6),
      watermark:,
      bounded: true,
      stored: described_class::Values.new(units: 5, events_count: 1),
      recomputed: described_class::Values.new(units: 5, events_count: 1)
    )
  end

  it "persists nothing" do
    expect { result }.not_to change { [RecurringAggregationSnapshot.count, Fee.count, CachedAggregation.count] }
  end

  context "when the stored units disagree with the events" do
    let(:snapshot_units) { 8 }

    it "reports the leaf" do
      expect(result.differences.sole).to have_attributes(
        stored: described_class::Values.new(units: 8, events_count: 1),
        recomputed: described_class::Values.new(units: 5, events_count: 1)
      )
    end
  end

  context "with pricing group keys" do
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, properties: {amount: "1", pricing_group_keys: ["region"]})
    end

    before do
      RecurringAggregationSnapshot.delete_all
      create_event(timestamp: Time.zone.parse("2022-03-11"), value: 2, created_at: watermark - 1.hour, region: "eu")
      create_snapshot(grouped_by: {"region" => nil}, units: 5, events_count: 1)
    end

    it "reports a group missing from the stored rows" do
      expect(result.differences.sole).to have_attributes(
        grouped_by: {"region" => "eu"},
        stored: nil,
        recomputed: described_class::Values.new(units: 2, events_count: 1)
      )
    end
  end

  context "with a charge filter" do
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
    let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "1"}) }

    before do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
      create_event(timestamp: Time.zone.parse("2022-03-11"), value: 2, created_at: watermark - 1.hour, region: "eu")
    end

    context "when the filter is stored at an older watermark" do
      before do
        create_event(timestamp: Time.zone.parse("2022-03-12"), value: 4, created_at: watermark - 2.minutes, region: "eu")
        create_snapshot(charge_filter:, watermark: watermark - 5.minutes, units: 2, events_count: 1)
      end

      it "recomputes each bucket at its own watermark" do
        expect(result.differences).to be_empty
        expect(result.rows.map { [it.charge_filter_id, it.watermark, it.stored] }).to match_array(
          [
            [nil, watermark, described_class::Values.new(units: 5, events_count: 1)],
            [charge_filter.id, watermark - 5.minutes, described_class::Values.new(units: 2, events_count: 1)]
          ]
        )
      end
    end

    context "when the filter has no stored row" do
      it "reports it at the latest watermark" do
        expect(result.differences.sole).to have_attributes(
          charge_filter_id: charge_filter.id,
          watermark:,
          stored: nil,
          recomputed: described_class::Values.new(units: 2, events_count: 1)
        )
      end
    end

    context "when the default bucket has no row" do
      before do
        RecurringAggregationSnapshot.delete_all
        create_snapshot(charge_filter:, units: 2, events_count: 1)
      end

      it "reports the missing period marker" do
        expect(result.charges_without_marker).to eq([charge.id])
      end
    end
  end

  context "with a weighted sum billable metric" do
    let(:billable_metric) { create(:weighted_sum_billable_metric, organization:, recurring: true, field_name: "value") }
    let(:snapshot_units) { 8 }

    it "marks its rows as not bounded by the watermark" do
      expect(result.rows.sole).to have_attributes(
        bounded: false,
        stored: described_class::Values.new(units: 8, events_count: 1),
        recomputed: described_class::Values.new(units: 8, events_count: 0)
      )
    end

    it "rolls back the recurring value the recompute writes" do
      expect { result }.not_to change(CachedAggregation, :count)
    end
  end

  context "with a fee of the period outside an invoice" do
    let(:charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: false, properties: {amount: "1"})
    end

    before do
      create(:charge_fee, invoice: nil, subscription:, organization:, charge:,
        properties: {
          charges_from_datetime: started_at.iso8601(3),
          charges_to_datetime: to_datetime.iso8601(3)
        })
    end

    it "computes the period again" do
      expect(result).to be_success
      expect(result.differences).to be_empty
      expect(result.rows.sole.recomputed).to eq(described_class::Values.new(units: 5, events_count: 1))
    end
  end

  context "without an invoice for the period" do
    before { InvoiceSubscription.delete_all }

    it "does not audit the charge" do
      expect(result.charges_without_invoice).to eq([charge.id])
      expect(result.rows).to be_empty
    end
  end

  context "without a snapshot" do
    before { RecurringAggregationSnapshot.delete_all }

    it "audits nothing" do
      expect(result.audited_charges_count).to eq(1)
      expect(result.snapshot_charges_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end

  context "with a non recurring billable metric" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }

    it "audits nothing" do
      expect(result.audited_charges_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end
end
