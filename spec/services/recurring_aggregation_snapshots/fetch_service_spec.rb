# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::FetchService do
  subject(:fetch_service) do
    described_class.new(subscription:, charge:, charge_filter:, grouped_by_keys:, from_datetime:)
  end

  let(:organization) { create(:organization) }
  let(:charge) { create(:standard_charge, organization:) }
  let(:subscription) { create(:subscription, organization:, plan: charge.plan) }
  let(:charge_filter) { nil }
  let(:grouped_by_keys) { nil }
  let(:from_datetime) { Time.zone.parse("2026-10-01T00:00:00") }
  let(:previous_to_datetime) { Time.zone.parse("2026-09-30T23:59:59") }
  let(:watermark) { Time.zone.parse("2026-10-01T00:05:00") }

  def create_snapshot(**attributes)
    create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, **attributes)
  end

  describe "#call" do
    context "without snapshot" do
      it "returns no snapshot" do
        result = fetch_service.call

        expect(result).to be_success
        expect(result.snapshots).to be_nil
      end
    end

    context "with snapshots of several periods" do
      before do
        create_snapshot(to_datetime: previous_to_datetime - 1.month, units: 4)
        create_snapshot(to_datetime: previous_to_datetime, units: 10, watermark:)
        create_snapshot(to_datetime: from_datetime + 1.month - 1.second, units: 20)
      end

      it "returns the snapshot of the latest period closed before from_datetime" do
        expect(fetch_service.call.snapshots).to eq(
          [
            described_class::Snapshot.new(grouped_by: {}, units: 10, to_datetime: previous_to_datetime, watermark:)
          ]
        )
      end
    end

    context "with snapshots of another charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:) }

      before do
        create_snapshot(to_datetime: previous_to_datetime, units: 10)
        create_snapshot(to_datetime: previous_to_datetime - 1.month, charge_filter:, units: 4)
      end

      it "returns the snapshot of the charge filter" do
        expect(fetch_service.call.snapshots.map(&:units)).to eq([4])
      end
    end

    context "with the default bucket of a charge with filters" do
      let(:charge_filter) { build(:charge_filter, charge:) }

      before do
        create_snapshot(to_datetime: previous_to_datetime, units: 10)
        create_snapshot(to_datetime: previous_to_datetime, charge_filter: create(:charge_filter, charge:), units: 4)
      end

      it "returns the snapshot without charge filter" do
        expect(fetch_service.call.snapshots.map(&:units)).to eq([10])
      end
    end

    context "with groups" do
      let(:grouped_by_keys) { %w[region] }

      before do
        create_snapshot(to_datetime: previous_to_datetime - 1.month, grouped_by: {"region" => "apac"}, units: 1)
        create_snapshot(to_datetime: previous_to_datetime, grouped_by: {"region" => "eu"}, units: 3)
        create_snapshot(to_datetime: previous_to_datetime, grouped_by: {"region" => "us"}, units: 0)
      end

      it "returns every group of the latest period" do
        expect(fetch_service.call.snapshots.map { [it.grouped_by, it.units] })
          .to match_array([[{"region" => "eu"}, 3], [{"region" => "us"}, 0]])
      end
    end

    context "when the grouped_by keys changed since the snapshot" do
      let(:grouped_by_keys) { %w[region country] }

      before { create_snapshot(to_datetime: previous_to_datetime, grouped_by: {"region" => "eu"}, units: 3) }

      it "returns no snapshot" do
        expect(fetch_service.call.snapshots).to be_nil
      end
    end

    context "when the charge is no longer grouped" do
      before { create_snapshot(to_datetime: previous_to_datetime, grouped_by: {"region" => "eu"}, units: 3) }

      it "returns no snapshot" do
        expect(fetch_service.call.snapshots).to be_nil
      end
    end
  end
end
