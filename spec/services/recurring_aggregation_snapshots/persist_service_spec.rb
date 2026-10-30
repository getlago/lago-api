# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::PersistService do
  subject(:result) { described_class.call(subscription:, charge:, to_datetime:, watermark:, buckets:) }

  let(:organization) { create(:organization) }
  let(:charge) { create(:standard_charge, organization:) }
  let(:subscription) { create(:subscription, organization:, plan: charge.plan) }
  let(:charge_filter) { nil }
  let(:to_datetime) { Time.zone.parse("2026-09-30T23:59:59") }
  let(:watermark) { Time.zone.parse("2026-10-01T00:05:00") }
  let(:presentation_breakdowns) { [{groups: {"region" => "eu"}, value: BigDecimal(12)}] }
  let(:values) { [{grouped_by: {}, units: 12, events_count: 4, presentation_breakdowns:}] }
  let(:buckets) { [{charge_filter:, values:}] }

  let(:snapshots) { RecurringAggregationSnapshot.where(subscription:, charge:) }

  describe "#call" do
    it "persists the snapshot" do
      expect(result).to be_success

      expect(snapshots.sole).to have_attributes(
        organization_id: organization.id,
        billable_metric_id: charge.billable_metric_id,
        charge_filter_id: nil,
        grouped_by: {},
        to_datetime:,
        watermark:,
        units: 12,
        events_count: 4,
        presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "12.0"}]
      )
    end

    context "with groups" do
      let(:values) do
        [
          {grouped_by: {"region" => "eu"}, units: 3, events_count: 2},
          {grouped_by: {"region" => "us"}, units: 0, events_count: 1}
        ]
      end

      it "persists one snapshot per group" do
        result

        expect(snapshots.pluck(:grouped_by, :units, :events_count)).to match_array([[{"region" => "eu"}, 3, 2], [{"region" => "us"}, 0, 1]])
      end
    end

    context "with a persisted charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:) }

      it "scopes the snapshot to the charge filter" do
        result

        expect(snapshots.sole.charge_filter_id).to eq(charge_filter.id)
      end
    end

    context "with the default bucket of a charge with filters" do
      let(:charge_filter) { build(:charge_filter, charge:) }

      it "persists the snapshot without charge filter" do
        result

        expect(snapshots.sole.charge_filter_id).to be_nil
      end
    end

    context "with several buckets" do
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:buckets) do
        [
          {charge_filter:, values: [{grouped_by: {}, units: 3, events_count: 2}]},
          {charge_filter: build(:charge_filter, charge:), values: [{grouped_by: {}, units: 0, events_count: 0}]}
        ]
      end

      it "persists the snapshots of every bucket" do
        result

        expect(snapshots.pluck(:charge_filter_id, :units)).to match_array([[charge_filter.id, 3], [nil, 0]])
      end
    end

    context "when the snapshot of the period already exists" do
      before do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 5, events_count: 1,
          watermark: watermark - 1.day)
      end

      it "replaces it" do
        result

        expect(snapshots.sole).to have_attributes(
          units: 12,
          events_count: 4,
          presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "12.0"}],
          watermark:
        )
      end
    end

    context "when the period has a snapshot of a group missing from the values" do
      let(:existing_watermark) { watermark - 1.day }

      before do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:,
          grouped_by: {"region" => "us"}, units: 5, watermark: existing_watermark)
      end

      it "deletes it" do
        result

        expect(snapshots.pluck(:grouped_by, :units)).to eq([[{}, 12]])
      end

      context "with a later watermark" do
        let(:existing_watermark) { watermark + 1.minute }

        it "keeps the period as the later run left it" do
          result

          expect(snapshots.pluck(:grouped_by, :units)).to eq([[{"region" => "us"}, 5]])
        end
      end
    end

    context "when the period has a snapshot of a filter missing from the buckets" do
      let(:other_filter) { create(:charge_filter, charge:) }

      before do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, charge_filter: other_filter, to_datetime:,
          units: 5, watermark: watermark - 1.day)
      end

      it "deletes it" do
        result

        expect(snapshots.pluck(:charge_filter_id, :units)).to eq([[nil, 12]])
      end
    end

    context "when the snapshot of the period has a later watermark" do
      before do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 15, events_count: 6,
          watermark: watermark + 1.minute)
      end

      it "keeps the snapshot" do
        result

        expect(snapshots.sole).to have_attributes(units: 15, events_count: 6, watermark: watermark + 1.minute)
      end
    end

    context "when a run with a later watermark left a group of the values out" do
      let(:values) do
        [
          {grouped_by: {"region" => "eu"}, units: 3, events_count: 2},
          {grouped_by: {"region" => "us"}, units: 4, events_count: 1}
        ]
      end

      before do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:,
          grouped_by: {"region" => "eu"}, units: 8, watermark: watermark + 1.minute)
      end

      it "does not bring the group back" do
        result

        expect(snapshots.pluck(:grouped_by, :units)).to eq([[{"region" => "eu"}, 8]])
      end
    end

    context "when a run with a later watermark left a filter empty" do
      let(:charge_filter) { create(:charge_filter, charge:) }

      before do
        # The later run kept only the marker of the default bucket: the filter dropped to zero units
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:,
          units: 0, watermark: watermark + 1.minute)
      end

      it "does not bring the filter back" do
        result

        expect(snapshots.pluck(:charge_filter_id, :units, :watermark)).to eq([[nil, 0, watermark + 1.minute]])
      end
    end

    it "serializes the runs of the period" do
      allow(RecurringAggregationSnapshots::LockService).to receive(:call!).and_call_original

      result

      expect(RecurringAggregationSnapshots::LockService).to have_received(:call!).with(subscription:, charge:, to_datetime:)
    end

    context "when a snapshot exists for another period" do
      before do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime: to_datetime - 1.month, units: 5)
      end

      it "keeps it and persists a new one" do
        result

        expect(snapshots.order(:to_datetime).pluck(:units)).to eq([5, 12])
      end
    end

    context "without values" do
      let(:values) { [] }

      it "persists nothing" do
        expect(result).to be_success
        expect(snapshots).to be_empty
      end

      context "when the period has a snapshot" do
        before do
          create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 5, watermark: watermark - 1.day)
        end

        it "deletes it" do
          result

          expect(snapshots).to be_empty
        end
      end
    end
  end
end
