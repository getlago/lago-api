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

  def create_filter(**attributes)
    create(:charge_filter, charge:, created_at: watermark - 1.month, updated_at: watermark - 1.month, **attributes)
  end

  def create_filter_value(charge_filter, **attributes)
    create(:charge_filter_value, charge_filter:, created_at: watermark - 1.month, updated_at: watermark - 1.month, **attributes)
  end

  def create_snapshot(**attributes)
    create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, watermark:, **attributes)
  end

  describe ".readable?" do
    subject(:readable) { described_class.readable?(metered_item:, billing_context:) }

    let(:billable_metric) { build_stubbed(:sum_billable_metric, :recurring) }
    let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billable_metric:, billing_segment: nil) }
    let(:billing_context) { Billing::Context.from(subscription:) }

    before { organization.enable_feature_flag!(:persisted_recurring_values) }

    it { is_expected.to be(true) }

    context "without the persisted_recurring_values feature flag" do
      before { organization.disable_feature_flag!(:persisted_recurring_values) }

      it { is_expected.to be(false) }
    end

    context "with a metric that is not recurring" do
      let(:billable_metric) { build_stubbed(:sum_billable_metric) }

      it { is_expected.to be(false) }
    end

    context "with an aggregation type without snapshots" do
      let(:billable_metric) { build_stubbed(:billable_metric, :recurring, aggregation_type: "count_agg") }

      it { is_expected.to be(false) }
    end
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
      let(:charge_filter) { create_filter }
      let(:filter_grouped_by) { {} }

      before do
        create_snapshot(to_datetime: previous_to_datetime, units: 10)
        create_snapshot(to_datetime: previous_to_datetime, charge_filter:, grouped_by: filter_grouped_by, units: 4)
        create_snapshot(to_datetime: previous_to_datetime, charge_filter: create_filter, units: 6)
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

        context "when the charge filter was edited after the latest period" do
          before { charge_filter.update!(updated_at: watermark + 1.minute) }

          it "returns no snapshot, as its grouping keys can have changed" do
            result = fetch_service.call

            expect(result.snapshots).to be_nil
            expect(result.period).to be_nil
          end
        end
      end

      context "when the charge filter was edited after the latest period" do
        before { charge_filter.update!(updated_at: watermark + 1.minute) }

        it "returns the snapshot of the charge filter, as its rows show their grouping keys" do
          expect(fetch_service.call.snapshots.map(&:units)).to eq([4])
        end
      end

      context "when created after the latest period" do
        let(:charge_filter) { create_filter(created_at: watermark + 1.minute) }

        it "returns no snapshot, as the snapshots of the period did not compute it" do
          result = fetch_service.call

          expect(result.snapshots).to be_nil
          expect(result.period).to be_nil
        end
      end

      context "when another filter of the charge was created after the latest period" do
        before { create_filter(created_at: watermark + 1.minute) }

        it "returns no snapshot, as the new filter can take events counted in this one" do
          result = fetch_service.call

          expect(result.snapshots).to be_nil
          expect(result.period).to be_nil
        end
      end

      context "when another filter of the charge was removed after the latest period" do
        before { create_filter(deleted_at: watermark + 1.minute) }

        it "returns no snapshot, as this filter can now match events counted in the removed one" do
          result = fetch_service.call

          expect(result.snapshots).to be_nil
          expect(result.period).to be_nil
        end
      end

      context "when another filter of the charge was removed before the latest period" do
        before { create_filter(deleted_at: watermark - 1.minute) }

        it "returns the snapshot of the charge filter" do
          expect(fetch_service.call.snapshots.map(&:units)).to eq([4])
        end
      end

      context "when a filter of another charge was created after the latest period" do
        before { create(:charge_filter, created_at: watermark + 1.minute) }

        it "returns the snapshot of the charge filter" do
          expect(fetch_service.call.snapshots.map(&:units)).to eq([4])
        end
      end

      context "when a value of another filter of the charge was edited after the latest period" do
        before { create_filter_value(create_filter, updated_at: watermark + 1.minute) }

        it "returns no snapshot, as the edited filter can take events counted in this one" do
          result = fetch_service.call

          expect(result.snapshots).to be_nil
          expect(result.period).to be_nil
        end
      end

      context "when a value of another filter of the charge was removed after the latest period" do
        before { create_filter_value(create_filter, deleted_at: watermark + 1.minute) }

        it "returns no snapshot, as this filter can now match events counted in the other one" do
          result = fetch_service.call

          expect(result.snapshots).to be_nil
          expect(result.period).to be_nil
        end
      end

      context "when a value of the charge filter was edited before the latest period" do
        before { create_filter_value(charge_filter, updated_at: watermark - 1.minute) }

        it "returns the snapshot of the charge filter" do
          expect(fetch_service.call.snapshots.map(&:units)).to eq([4])
        end
      end

      context "when a value of a filter of another charge was edited after the latest period" do
        before { create(:charge_filter_value, updated_at: watermark + 1.minute) }

        it "returns the snapshot of the charge filter" do
          expect(fetch_service.call.snapshots.map(&:units)).to eq([4])
        end
      end

      context "with another filter of the charge set to all values of a metric filter" do
        let(:region) do
          create(:billable_metric_filter, organization:, billable_metric: charge.billable_metric, key: "region", values: %w[eu us],
            created_at: watermark - 1.month, updated_at: watermark - 1.month)
        end
        let(:region_values) { [ChargeFilterValue::ALL_FILTER_VALUES] }

        before do
          create_filter_value(create_filter, billable_metric_filter: region, values: region_values)
          travel_to(watermark + 1.minute) { region.update!(values: new_region_values) }
        end

        context "when the metric filter gained a value after the latest period" do
          let(:new_region_values) { %w[eu us apac] }

          it "returns no snapshot, as the filter now takes events counted in this one" do
            result = fetch_service.call

            expect(result.snapshots).to be_nil
            expect(result.period).to be_nil
          end
        end

        context "when the metric filter lost a value after the latest period" do
          let(:new_region_values) { %w[eu] }

          it "returns no snapshot, as this filter can now match events counted in the other one" do
            result = fetch_service.call

            expect(result.snapshots).to be_nil
            expect(result.period).to be_nil
          end
        end

        context "when the filter lists the values of the metric filter" do
          let(:region_values) { %w[eu] }
          let(:new_region_values) { %w[eu us apac] }

          it "returns the snapshot of the charge filter" do
            expect(fetch_service.call.snapshots.map(&:units)).to eq([4])
          end
        end
      end

      context "when the charge filter groups on keys the default bucket does not" do
        let(:grouped_by_keys) { %w[region] }
        let(:filter_grouped_by) { {"region" => "eu"} }

        it "returns the snapshot of the charge filter" do
          expect(fetch_service.call.snapshots.map { [it.grouped_by, it.units] }).to eq([[{"region" => "eu"}, 4]])
        end
      end

      context "when the charge filter is grouped on other keys than its snapshot" do
        let(:grouped_by_keys) { %w[region] }

        it "returns no snapshot" do
          result = fetch_service.call

          expect(result.snapshots).to be_nil
          expect(result.period).to be_nil
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
        create_snapshot(to_datetime: previous_to_datetime, charge_filter: create_filter, units: 4)
      end

      it "returns the snapshot without charge filter" do
        expect(fetch_service.call.snapshots.map(&:units)).to eq([10])
      end

      context "when a filter was created after the latest period" do
        before { create_filter(created_at: watermark + 1.minute) }

        it "returns no snapshot, as the new filter takes events counted in the default bucket" do
          result = fetch_service.call

          expect(result.snapshots).to be_nil
          expect(result.period).to be_nil
        end
      end

      context "when a filter was removed after the latest period" do
        before { create_filter(deleted_at: watermark + 1.minute) }

        it "returns no snapshot, as the default bucket now matches events counted in the removed filter" do
          expect(fetch_service.call.snapshots).to be_nil
        end
      end

      context "when a metric filter a filter sets to all values gained a value after the latest period" do
        let(:region) do
          create(:billable_metric_filter, organization:, billable_metric: charge.billable_metric, key: "region", values: %w[eu us],
            created_at: watermark - 1.month, updated_at: watermark - 1.month)
        end

        before do
          create_filter_value(create_filter, billable_metric_filter: region, values: [ChargeFilterValue::ALL_FILTER_VALUES])
          travel_to(watermark + 1.minute) { region.update!(values: %w[eu us apac]) }
        end

        it "returns no snapshot, as the filter now takes events counted in the default bucket" do
          expect(fetch_service.call.snapshots).to be_nil
        end
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
