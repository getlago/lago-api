# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::ChargePeriod do
  subject(:charge_period) { described_class.new(subscription:, charge:, from_datetime:) }

  let(:organization) { create(:organization) }
  let(:charge) { create(:standard_charge, organization:) }
  let(:subscription) { create(:subscription, organization:, plan: charge.plan) }
  let(:from_datetime) { Time.zone.parse("2026-10-01T00:00:00") }
  let(:previous_to_datetime) { Time.zone.parse("2026-09-30T23:59:59") }
  let(:watermark) { Time.zone.parse("2026-10-01T00:05:00") }
  let(:eu_filter) { create_filter }
  let(:us_filter) { create_filter }

  def create_filter(**attributes)
    create(:charge_filter, charge:, created_at: watermark - 1.month, **attributes)
  end

  def create_snapshot(**attributes)
    create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, watermark:, **attributes)
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    count
  end

  describe "#period" do
    before do
      create_snapshot(to_datetime: previous_to_datetime - 1.month, units: 1)
      create_snapshot(to_datetime: previous_to_datetime, units: 10)
      create_snapshot(to_datetime: previous_to_datetime, charge_filter: eu_filter, units: 4)
      us_filter
    end

    it "returns the marker and the snapshots of the charge filter's bucket" do
      marker, records = charge_period.period(charge_filter: eu_filter)

      expect(marker).to have_attributes(charge_filter_id: nil, to_datetime: previous_to_datetime, units: 10)
      expect(records.map(&:units)).to eq([4])
      expect(charge_period.period(charge_filter: us_filter).last).to eq([])
      expect(charge_period.period(charge_filter: nil).last.map(&:units)).to eq([10])
    end

    it "loads the period once for all buckets" do
      first_bucket_queries = count_queries { charge_period.period(charge_filter: eu_filter) }
      other_buckets_queries = count_queries do
        [us_filter, nil].each { charge_period.period(charge_filter: it) }
      end

      expect(first_bucket_queries).to eq(3)
      expect(other_buckets_queries).to eq(0)
    end

    context "without a marker before from_datetime" do
      let(:from_datetime) { previous_to_datetime - 1.month }

      it "returns nil" do
        expect(charge_period.period(charge_filter: eu_filter)).to be_nil
      end
    end

    context "when a filter of the charge changed since the marker" do
      before { create_filter(created_at: watermark + 1.minute) }

      it "returns no marker nor snapshot" do
        expect(charge_period.period(charge_filter: eu_filter)).to eq([])
      end
    end
  end
end
