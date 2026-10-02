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
  let(:values) { [{grouped_by: {}, units: 12}] }

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
        units: 12
      )
    end

    context "with groups" do
      let(:values) do
        [
          {grouped_by: {"region" => "eu"}, units: 3},
          {grouped_by: {"region" => "us"}, units: 0}
        ]
      end

      it "persists one snapshot per group, zero units included" do
        persist_service.call

        expect(snapshots.pluck(:grouped_by, :units)).to match_array([[{"region" => "eu"}, 3], [{"region" => "us"}, 0]])
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
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 5, watermark: watermark - 1.day)
      end

      before { existing }

      it "updates the units and the watermark" do
        persist_service.call

        expect(snapshots.sole).to have_attributes(id: existing.id, units: 12, watermark:)
      end
    end

    context "when the snapshot of the period has a later watermark" do
      let(:existing) do
        create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 15, watermark: watermark + 1.minute)
      end

      before { existing }

      it "keeps the snapshot" do
        persist_service.call

        expect(snapshots.sole).to have_attributes(units: 15, watermark: watermark + 1.minute)
      end
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
    end
  end
end
