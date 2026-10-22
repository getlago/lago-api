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
    create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, watermark:, **attributes)
  end

  describe "#call" do
    context "without snapshot" do
      it "returns no snapshot" do
        result = fetch_service.call

        expect(result).to be_success
        expect(result.snapshots).to be_nil
        expect(result.period).to be_nil
      end
    end

    context "with snapshots of several periods" do
      before do
        create_snapshot(to_datetime: previous_to_datetime - 1.month, units: 4)
        create_snapshot(
          to_datetime: previous_to_datetime, units: 10, events_count: 3, watermark:,
          presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "10.0"}]
        )
        create_snapshot(to_datetime: from_datetime + 1.month - 1.second, units: 20)
      end

      it "returns the snapshot of the latest period closed before from_datetime" do
        result = fetch_service.call

        expect(result.period).to eq(described_class::Period.new(to_datetime: previous_to_datetime, watermark:))
        expect(result.snapshots).to eq(
          [
            described_class::Snapshot.new(
              grouped_by: {},
              units: 10,
              events_count: 3,
              presentation_breakdowns: [{groups: {"region" => "eu"}, value: "10.0"}],
              to_datetime: previous_to_datetime,
              watermark:
            )
          ]
        )
      end
    end

    context "with a snapshot of another organization" do
      before { create_snapshot(to_datetime: previous_to_datetime, units: 10, organization: create(:organization)) }

      it "returns no snapshot" do
        expect(fetch_service.call.snapshots).to be_nil
      end
    end

    context "with a charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:, created_at: watermark - 1.month) }

      before do
        create_snapshot(to_datetime: previous_to_datetime, units: 10)
        create_snapshot(to_datetime: previous_to_datetime, charge_filter:, units: 4)
        create_snapshot(to_datetime: previous_to_datetime, charge_filter: create(:charge_filter, charge:), units: 6)
      end

      it "returns the snapshot of the charge filter" do
        expect(fetch_service.call.snapshots.map(&:units)).to eq([4])
      end

      context "without a snapshot of its own in the latest period" do
        before { RecurringAggregationSnapshot.where(charge_filter:).delete_all }

        it "returns no snapshot but the period, as it had neither units nor events" do
          result = fetch_service.call

          expect(result.snapshots).to eq([])
          expect(result.period).to eq(described_class::Period.new(to_datetime: previous_to_datetime, watermark:))
        end
      end

      context "when created after the latest period" do
        let(:charge_filter) { create(:charge_filter, charge:, created_at: watermark + 1.minute) }

        it "returns no snapshot, as the snapshots of the period did not compute it" do
          result = fetch_service.call

          expect(result.snapshots).to be_nil
          expect(result.period).to be_nil
        end
      end

      context "when its snapshot belongs to an older run of the period" do
        before do
          RecurringAggregationSnapshot.where(charge_filter:).update_all(watermark: watermark - 1.hour) # rubocop:disable Rails/SkipsModelValidations
        end

        it "ignores it" do
          expect(fetch_service.call.snapshots).to eq([])
        end
      end

      context "without the marker of the default bucket" do
        before { RecurringAggregationSnapshot.where(charge_filter_id: nil).delete_all }

        it "returns no snapshot" do
          expect(fetch_service.call.snapshots).to be_nil
        end
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
