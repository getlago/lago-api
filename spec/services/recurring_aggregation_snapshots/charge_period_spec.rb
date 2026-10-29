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

      expect(first_bucket_queries).to eq(5)
      expect(other_buckets_queries).to eq(0)
    end

    context "with charge_filter_ids" do
      subject(:charge_period) { described_class.new(subscription:, charge:, from_datetime:, charge_filter_ids: [eu_filter.id]) }

      before { create_snapshot(to_datetime: previous_to_datetime, charge_filter: us_filter, units: 2) }

      it "loads only the default bucket and those buckets" do
        expect(charge_period.period(charge_filter: eu_filter).last.map(&:units)).to eq([4])
        expect(charge_period.period(charge_filter: nil).last.map(&:units)).to eq([10])
        expect(charge_period.period(charge_filter: us_filter).last).to eq([])
      end
    end

    context "without a marker before from_datetime" do
      let(:from_datetime) { previous_to_datetime - 1.month }

      it "returns nil" do
        expect(charge_period.period(charge_filter: eu_filter)).to be_nil
      end
    end

    context "with grouped_by_values" do
      subject(:charge_period) { described_class.new(subscription:, charge:, from_datetime:, grouped_by_values:) }

      let(:grouped_by_values) { {"region" => "eu", "cloud" => nil} }

      before do
        [
          {"region" => "eu", "cloud" => nil},
          {"region" => "eu", "cloud" => "aws"},
          {"region" => "us", "cloud" => nil}
        ].each_with_index do |grouped_by, index|
          create_snapshot(to_datetime: previous_to_datetime, charge_filter: eu_filter, grouped_by:, units: 100 + index)
        end
      end

      it "loads the group's snapshots and the first snapshot of each bucket" do
        first_eu_units = RecurringAggregationSnapshot.where(charge_filter: eu_filter).order(:id).first.units

        expect(charge_period.period(charge_filter: eu_filter).last.map(&:units)).to match_array([100, first_eu_units].uniq(&:to_d))
        expect(charge_period.period(charge_filter: nil).last.map(&:units)).to eq([10])
      end

      context "with a blank value stored for a missing one" do
        let(:grouped_by_values) { {"region" => "apac", "cloud" => ""} }

        before do
          create_snapshot(to_datetime: previous_to_datetime, charge_filter: eu_filter, grouped_by: {"region" => "apac", "cloud" => " "}, units: 7)
        end

        it "loads it" do
          expect(charge_period.period(charge_filter: eu_filter).last.map(&:units)).to include(7)
        end
      end

      context "without a value for a key" do
        let(:grouped_by_values) { {"region" => "eu"} }

        it "loads every value of that key" do
          expect(charge_period.period(charge_filter: eu_filter).last.map(&:units)).to include(100, 101)
        end
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
