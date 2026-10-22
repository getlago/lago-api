# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::PersistService do
  subject(:persist_service) do
    described_class.new(subscription:, charge:, charge_filter:, to_datetime:, watermark:, values:)
  end

  let(:organization) { create(:organization) }
  let(:charge) { create(:standard_charge, organization:) }
  let(:subscription) { create(:subscription, organization:, plan: charge.plan) }
  let(:charge_filter) { nil }
  let(:to_datetime) { Time.zone.parse("2026-09-30T23:59:59") }
  let(:watermark) { Time.zone.parse("2026-10-01T00:05:00") }
  let(:presentation_breakdowns) { [{groups: {"region" => "eu"}, value: BigDecimal(12)}] }
  let(:values) { [{grouped_by: {}, units: 12, events_count: 4, presentation_breakdowns:}] }

  let(:snapshots) { RecurringAggregationSnapshot.where(subscription:, charge:) }

  describe "#call" do
    it "persists the snapshot" do
      expect(persist_service.call).to be_success

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
        persist_service.call

        expect(snapshots.pluck(:grouped_by, :units, :events_count)).to match_array([[{"region" => "eu"}, 3, 2], [{"region" => "us"}, 0, 1]])
      end
    end

    context "with a persisted charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:) }

      it "scopes the snapshot to the charge filter" do
        persist_service.call

        expect(snapshots.sole.charge_filter_id).to eq(charge_filter.id)
      end
    end

    context "with the default bucket of a charge with filters" do
      let(:charge_filter) { build(:charge_filter, charge:) }

      it "persists the snapshot without charge filter" do
        persist_service.call

        expect(snapshots.sole.charge_filter_id).to be_nil
      end
    end

    context "when the snapshot of the period already exists" do
      let(:existing) do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 5, events_count: 1,
          watermark: watermark - 1.day)
      end

      before { existing }

      it "replaces it" do
        persist_service.call

        expect(snapshots.sole).to have_attributes(
          units: 12,
          events_count: 4,
          presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "12.0"}],
          watermark:
        )
      end
    end

    context "when the period has a snapshot of a group missing from the values" do
      let(:existing) do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:,
          grouped_by: {"region" => "us"}, units: 5, watermark: watermark - 1.day)
      end

      before { existing }

      it "deletes it" do
        persist_service.call

        expect(snapshots.pluck(:grouped_by, :units)).to eq([[{}, 12]])
      end

      context "with a later watermark" do
        let(:existing) do
          create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:,
            grouped_by: {"region" => "us"}, units: 5, watermark: watermark + 1.minute)
        end

        it "keeps the period as the later run left it" do
          persist_service.call

          expect(snapshots.pluck(:grouped_by, :units)).to eq([[{"region" => "us"}, 5]])
        end
      end
    end

    context "when the snapshot of the period has a later watermark" do
      let(:existing) do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 15, events_count: 6,
          watermark: watermark + 1.minute)
      end

      before { existing }

      it "keeps the snapshot" do
        persist_service.call

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
        persist_service.call

        expect(snapshots.pluck(:grouped_by, :units)).to eq([[{"region" => "eu"}, 8]])
      end
    end

    it "serializes the runs of the period" do
      allow(RecurringAggregationSnapshot).to receive(:with_advisory_lock).and_call_original

      persist_service.call

      expect(RecurringAggregationSnapshot).to have_received(:with_advisory_lock).with(
        "recurring_aggregation_snapshots_#{subscription.id}_#{charge.id}__#{to_datetime.iso8601(6)}",
        transaction: true
      )
    end

    context "when a snapshot exists for another period" do
      before do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime: to_datetime - 1.month, units: 5)
      end

      it "keeps it and persists a new one" do
        persist_service.call

        expect(snapshots.order(:to_datetime).pluck(:units)).to eq([5, 12])
      end
    end

    context "without values" do
      let(:values) { [] }

      it "persists nothing" do
        expect(persist_service.call).to be_success
        expect(snapshots).to be_empty
      end

      context "when the period has a snapshot" do
        before do
          create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 5, watermark: watermark - 1.day)
        end

        it "deletes it" do
          persist_service.call

          expect(snapshots).to be_empty
        end
      end
    end
  end
end
