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
        create_snapshot(
          to_datetime: previous_to_datetime, units: 10, events_count: 3, watermark:,
          presentation_breakdowns: [{"groups" => {"region" => "eu"}, "value" => "10.0"}]
        )
        create_snapshot(to_datetime: from_datetime + 1.month - 1.second, units: 20)
      end

      it "returns the snapshot of the latest period closed before from_datetime" do
        expect(fetch_service.call.snapshots).to eq(
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

    context "with a previous subscription" do
      let(:billable_metric) { charge.billable_metric }
      let(:previous_charge) { create(:standard_charge, organization:, billable_metric:) }
      let(:previous_subscription) { create(:subscription, organization:, plan: previous_charge.plan, customer: subscription.customer) }
      let(:termination_datetime) { from_datetime + 1.second }

      before { subscription.update!(previous_subscription:) }

      def create_previous_snapshot(**attributes)
        create(
          :recurring_aggregation_snapshot,
          organization:, subscription: previous_subscription, charge: previous_charge, watermark:, **attributes
        )
      end

      context "when the previous subscription has a snapshot of the same billable metric" do
        before do
          create_previous_snapshot(to_datetime: previous_to_datetime, units: 4)
          create_previous_snapshot(to_datetime: termination_datetime, units: 7, events_count: 2)
        end

        it "returns the latest snapshot of the previous subscription" do
          expect(fetch_service.call.snapshots).to eq(
            [
              described_class::Snapshot.new(
                grouped_by: {}, units: 7, events_count: 2, to_datetime: termination_datetime, watermark:
              )
            ]
          )
        end
      end

      context "when the subscription has a snapshot of its own" do
        before do
          create_previous_snapshot(to_datetime: termination_datetime, units: 7)
          create_snapshot(to_datetime: previous_to_datetime, units: 10)
        end

        it "returns its own snapshot" do
          expect(fetch_service.call.snapshots.map(&:units)).to eq([10])
        end
      end

      context "when the previous charge has another billable metric" do
        let(:previous_charge) { create(:standard_charge, organization:) }

        before { create_previous_snapshot(to_datetime: termination_datetime, units: 7) }

        it "returns no snapshot" do
          expect(fetch_service.call.snapshots).to be_nil
        end
      end

      context "when several previous charges match" do
        let(:other_previous_charge) { create(:standard_charge, organization:, billable_metric:, plan: previous_charge.plan) }

        before do
          create_previous_snapshot(to_datetime: termination_datetime, units: 7)
          create_previous_snapshot(to_datetime: termination_datetime - 1.month, charge: other_previous_charge, units: 3)
        end

        it "returns no snapshot" do
          expect(fetch_service.call.snapshots).to be_nil
        end
      end

      context "when the subscription has own snapshots grouped on other keys" do
        before do
          create_previous_snapshot(to_datetime: termination_datetime, units: 7)
          create_snapshot(to_datetime: previous_to_datetime, grouped_by: {"region" => "eu"}, units: 10)
        end

        it "returns no snapshot" do
          expect(fetch_service.call.snapshots).to be_nil
        end
      end

      context "with groups" do
        let(:grouped_by_keys) { %w[region] }

        before do
          create_previous_snapshot(to_datetime: termination_datetime, grouped_by: {"region" => "eu"}, units: 3)
          create_previous_snapshot(to_datetime: termination_datetime, grouped_by: {"region" => "us"}, units: 0)
        end

        it "returns every group of the previous subscription" do
          expect(fetch_service.call.snapshots.map { [it.grouped_by, it.units] })
            .to match_array([[{"region" => "eu"}, 3], [{"region" => "us"}, 0]])
        end
      end

      context "when the grouped_by keys of the previous charge differ" do
        let(:grouped_by_keys) { %w[region] }

        before { create_previous_snapshot(to_datetime: termination_datetime, grouped_by: {"country" => "fr"}, units: 7) }

        it "returns no snapshot" do
          expect(fetch_service.call.snapshots).to be_nil
        end
      end

      context "with charge filters" do
        let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
        let(:charge_filter) { create_filter(charge, %w[eu]) }
        let(:previous_charge_filter) { create_filter(previous_charge, %w[eu]) }

        def create_filter(target_charge, values)
          create(:charge_filter, charge: target_charge).tap do |filter|
            create(:charge_filter_value, charge_filter: filter, billable_metric_filter:, values:)
          end
        end

        before do
          create_previous_snapshot(to_datetime: termination_datetime, units: 7)
          create_previous_snapshot(to_datetime: termination_datetime, charge_filter: previous_charge_filter, units: 3)
        end

        it "returns the snapshot of the filter with the same values" do
          expect(fetch_service.call.snapshots.map(&:units)).to eq([3])
        end

        context "with the default bucket" do
          let(:charge_filter) do
            create_filter(charge, %w[eu])
            build(:charge_filter, charge:)
          end

          it "returns the snapshot without charge filter" do
            expect(fetch_service.call.snapshots.map(&:units)).to eq([7])
          end
        end

        context "when the previous charge has other filters" do
          before { create_filter(previous_charge, %w[us]) }

          it "returns no snapshot" do
            expect(fetch_service.call.snapshots).to be_nil
          end
        end

        context "when the previous charge is discarded" do
          let(:charge) { create(:standard_charge, organization:) }
          let(:charge_filter) { build(:charge_filter, charge:) }

          before { Charges::DestroyService.call!(charge: previous_charge) }

          it "returns no snapshot" do
            expect(fetch_service.call.snapshots).to be_nil
          end
        end

        context "when the filter values differ" do
          let(:previous_charge_filter) { create_filter(previous_charge, %w[us]) }

          it "returns no snapshot" do
            expect(fetch_service.call.snapshots).to be_nil
          end
        end
      end
    end
  end
end
