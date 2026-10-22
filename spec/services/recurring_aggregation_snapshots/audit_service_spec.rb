# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::AuditService do
  subject(:result) { described_class.call(subscription:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:to_datetime) { Time.zone.parse("2022-03-31T23:59:59") }

  let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:fee_units) { 5 }

  before do
    create(:invoice_subscription, subscription:, invoice:, charges_to_datetime: to_datetime)
    create_snapshot(units: 5, events_count: 2)
    create_fee(total_aggregated_units: fee_units, events_count: 2)
  end

  def create_snapshot(**attributes)
    create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, **attributes)
  end

  def create_fee(**attributes)
    create(:charge_fee, organization:, invoice:, subscription:, charge:, **attributes)
  end

  def row(**attributes)
    described_class::Row.new(
      charge_id: charge.id,
      charge_filter_id: nil,
      grouped_by: {},
      to_datetime:,
      snapshot_units: 5,
      fee_units: 5,
      snapshot_events_count: 2,
      fee_events_count: 2,
      **attributes
    )
  end

  it "compares the snapshot with the fee of its period" do
    expect(result).to be_success
    expect(result.rows).to eq([row])
    expect(result.differences).to be_empty
    expect(result.periods_without_invoice).to be_empty
  end

  context "when the fee billed other units" do
    let(:fee_units) { 8 }

    it "reports the leaf" do
      expect(result.differences).to eq([row(fee_units: 8)])
    end
  end

  context "with fees outside the period's billing" do
    before do
      create_fee(total_aggregated_units: 3, pay_in_advance_event_id: SecureRandom.uuid)
      create_fee(total_aggregated_units: 3, invoice: create(:invoice, organization:, customer:))
    end

    it "ignores them" do
      expect(result.differences).to be_empty
    end
  end

  context "with pricing groups" do
    before do
      create_snapshot(grouped_by: {"region" => "eu"}, units: 4, events_count: 1)
      create_fee(grouped_by: {"region" => "us"}, total_aggregated_units: 3, events_count: 1)
    end

    it "counts a group missing on one side as zero" do
      expect(result.differences).to match_array(
        [
          row(grouped_by: {"region" => "eu"}, snapshot_units: 4, fee_units: 0, snapshot_events_count: 1, fee_events_count: 0),
          row(grouped_by: {"region" => "us"}, snapshot_units: 0, fee_units: 3, snapshot_events_count: 0, fee_events_count: 1)
        ]
      )
    end
  end

  context "with a zero-unit marker and no fee" do
    before do
      Fee.delete_all
      RecurringAggregationSnapshot.delete_all
      create_snapshot(grouped_by: {"region" => nil}, units: 0, events_count: 0)
    end

    it "reports no difference" do
      expect(result.rows).to eq([row(snapshot_units: 0, fee_units: 0, snapshot_events_count: 0, fee_events_count: 0)])
      expect(result.differences).to be_empty
    end
  end

  context "with a charge filter" do
    let(:charge_filter) { create(:charge_filter, charge:) }

    before do
      create_snapshot(charge_filter:, units: 2, events_count: 1)
      create_fee(charge_filter:, total_aggregated_units: 2, events_count: 1)
    end

    it "compares each bucket with its own fee" do
      expect(result.differences).to be_empty
      expect(result.rows.map(&:charge_filter_id)).to match_array([nil, charge_filter.id])
    end
  end

  context "with a weighted sum billable metric" do
    let(:billable_metric) { create(:weighted_sum_billable_metric, organization:, recurring: true) }

    it "compares the units only" do
      expect(result.rows).to eq([row(snapshot_events_count: nil, fee_events_count: nil)])
    end
  end

  context "without an invoice for the period" do
    before { InvoiceSubscription.delete_all }

    it "reports the period" do
      expect(result.rows).to be_empty
      expect(result.periods_without_invoice).to eq([described_class::Period.new(charge_id: charge.id, to_datetime:)])
    end
  end

  context "with a snapshot of another subscription" do
    before do
      other_subscription = create(:subscription, organization:, customer:, plan:)
      create(:recurring_aggregation_snapshot, organization:, subscription: other_subscription, charge:, to_datetime:, units: 9)
    end

    it "ignores it" do
      expect(result.rows).to eq([row])
    end
  end
end
