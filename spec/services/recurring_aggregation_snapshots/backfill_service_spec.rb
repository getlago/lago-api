# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::BackfillService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:plan) { create(:plan, organization:, interval: "monthly") }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at: Time.utc(2026, 3, 1), subscription_at: Time.utc(2026, 3, 1)) }
  let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "value") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:snapshots) { RecurringAggregationSnapshot.where(subscription:) }
  let(:now) { Time.utc(2026, 5, 10) }
  let(:march_end) { Time.utc(2026, 3, 31).end_of_day }
  let(:april_end) { Time.utc(2026, 4, 30).end_of_day }
  let(:invoiced_periods) { [[Time.utc(2026, 3, 1), march_end], [Time.utc(2026, 4, 1), april_end]] }

  def invoice_period(from, to)
    create(
      :invoice_subscription,
      subscription:,
      invoice: create(:invoice, organization:, customer:),
      recurring: true,
      invoicing_reason: :subscription_periodic,
      timestamp: to + 1.second,
      from_datetime: from,
      to_datetime: to,
      charges_from_datetime: from,
      charges_to_datetime: to
    )
  end

  def send_event(value, timestamp:)
    create(:event, organization:, subscription:, code: billable_metric.code, timestamp:,
      created_at: [timestamp, now - 1.hour].min, properties: {value:})
  end

  around { |example| travel_to(now) { example.run } }

  before do
    charge
    invoiced_periods.each { invoice_period(*it) }

    send_event(10, timestamp: Time.utc(2026, 3, 5))
    send_event(5, timestamp: Time.utc(2026, 4, 10))
    send_event(3, timestamp: Time.utc(2026, 5, 3))
  end

  it "writes the snapshot of the latest invoiced period only" do
    expect(result).to be_success
    expect(result.written_charges).to eq([charge])
    expect(result.skipped_charges).to eq([])
    expect(result.failed_charges).to eq([])

    # 10 in March + 5 in April, the May event is after the period
    expect(snapshots.sole).to have_attributes(
      charge_id: charge.id,
      charge_filter_id: nil,
      to_datetime: april_end.floor(6),
      watermark: now - RecurringAggregationSnapshot::WATERMARK_LAG,
      units: 15,
      events_count: 2
    )
  end

  it "creates no fee" do
    expect { result }.not_to change(Fee, :count)
  end

  context "with a snapshot already stored for the period" do
    before do
      create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime: april_end,
        watermark: Time.utc(2026, 5, 1), units: 99, events_count: 9)
    end

    it "replaces it" do
      result

      expect(snapshots.sole).to have_attributes(units: 15, events_count: 2, watermark: now - RecurringAggregationSnapshot::WATERMARK_LAG)
    end
  end

  context "when the latest invoiced period has empty charge boundaries" do
    let(:invoiced_periods) { super() + [[Time.utc(2026, 5, 1), Time.utc(2026, 5, 1)]] }

    it "writes the latest period with charges" do
      expect(result.invoice_subscription.charges_to_datetime).to eq(april_end.floor(6))
      expect(snapshots.sole).to have_attributes(to_datetime: april_end.floor(6), units: 15)
    end
  end

  context "with a charge whose metric is not eligible" do
    let(:unique_count_metric) { create(:unique_count_billable_metric, :recurring, organization:) }
    let(:non_recurring_metric) { create(:sum_billable_metric, organization:) }

    before do
      create(:standard_charge, plan:, billable_metric: unique_count_metric)
      create(:standard_charge, plan:, billable_metric: non_recurring_metric)
    end

    it "leaves it out" do
      expect(result.written_charges).to eq([charge])
      expect(snapshots.pluck(:charge_id)).to eq([charge.id])
    end
  end

  [
    ActiveRecord::StatementInvalid,
    Events::Stores::Clickhouse::MemoryLimitError,
    Errno::ECONNRESET,
    Net::ReadTimeout
  ].each do |error|
    context "when a charge raises #{error} on the events store" do
      let(:other_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "value") }
      let(:other_charge) { create(:standard_charge, plan:, billable_metric: other_metric) }

      before do
        other_charge
        allow(Fees::ChargeService).to receive(:call).and_wrap_original do |method, **args|
          raise error if args[:metered_item].charge == charge

          method.call(**args)
        end
      end

      it "reports it as failed and backfills the other charges" do
        expect(result).to be_success
        expect(result.failed_charges).to eq([charge])
        expect(result.written_charges).to eq([other_charge])
        expect(snapshots.pluck(:charge_id)).to eq([other_charge.id])
      end
    end
  end

  context "when the charge aggregation fails" do
    before do
      allow(Fees::ChargeService).to receive(:call)
        .and_return(BaseService::Result.new.tap { it.service_failure!(code: "error", message: "failed") })
    end

    it "reports the charge as failed" do
      expect(result).to be_success
      expect(result.failed_charges).to eq([charge])
      expect(snapshots).to be_empty
    end
  end

  context "when the charge writes no snapshot" do
    before { allow(Fees::ChargeService).to receive(:call).and_return(BaseService::Result.new) }

    it "reports the charge as skipped" do
      expect(result.skipped_charges).to eq([charge])
      expect(result.written_charges).to eq([])
    end
  end

  context "without an invoiced period" do
    let(:invoiced_periods) { [] }

    it "writes nothing" do
      expect(result).to be_success
      expect(result.invoice_subscription).to be_nil
      expect(result.written_charges).to eq([])
      expect(snapshots).to be_empty
    end
  end

  context "with a subscription that is not active" do
    let(:subscription) do
      create(:subscription, :terminated, organization:, customer:, plan:, started_at: Time.utc(2026, 3, 1), subscription_at: Time.utc(2026, 3, 1))
    end

    it "fails" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      expect(result.error.code).to eq("subscription_not_active")
      expect(snapshots).to be_empty
    end
  end
end
