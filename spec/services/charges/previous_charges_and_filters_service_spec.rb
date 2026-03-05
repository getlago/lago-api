# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::PreviousChargesAndFiltersService do
  subject(:service) { described_class.new(charge:, charge_filter:, subscription:) }

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["enriched_events_aggregation"]) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :sum_agg, field_name: "value", recurring: true) }

  let(:previous_plan) { create(:plan, organization:) }
  let(:previous_charge) { create(:standard_charge, plan: previous_plan, billable_metric:) }
  let(:previous_subscription) { create(:subscription, plan: previous_plan, organization:, status: :terminated) }

  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:subscription) { create(:subscription, plan:, organization:, previous_subscription:) }

  let(:charge_filter) { nil }

  before do
    previous_charge
  end

  describe "#call" do
    context "when all conditions are met" do
      it "returns previous charge ids" do
        result = service.call

        expect(result.previous_charge_ids).to eq([previous_charge.id])
        expect(result.previous_charge_filter_ids).to eq([])
      end
    end

    context "with a chain of previous subscriptions" do
      let(:oldest_plan) { create(:plan, organization:) }
      let(:oldest_charge) { create(:standard_charge, plan: oldest_plan, billable_metric:) }
      let(:oldest_subscription) { create(:subscription, plan: oldest_plan, organization:, status: :terminated) }

      before do
        oldest_charge
        previous_subscription.update!(previous_subscription: oldest_subscription)
      end

      it "collects charge ids from all previous subscriptions" do
        result = service.call

        expect(result.previous_charge_ids).to match_array([previous_charge.id, oldest_charge.id])
      end
    end

    context "with charge filters" do
      let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, values: %w[aws gcp azure]) }
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:previous_charge_filter) { create(:charge_filter, charge: previous_charge) }

      before do
        create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["aws"])
        create(:charge_filter_value, charge_filter: previous_charge_filter, billable_metric_filter:, values: ["aws"])
      end

      it "returns matching previous charge filter ids" do
        result = service.call

        expect(result.previous_charge_ids).to eq([previous_charge.id])
        expect(result.previous_charge_filter_ids).to eq([previous_charge_filter.id])
      end

      context "when previous filter does not match" do
        before do
          previous_charge_filter.values.first.update!(values: ["gcp"])
        end

        it "does not include non-matching filter ids" do
          result = service.call

          expect(result.previous_charge_ids).to eq([previous_charge.id])
          expect(result.previous_charge_filter_ids).to eq([])
        end
      end
    end

    context "when subscription has no previous subscription" do
      let(:subscription) { create(:subscription, plan:, organization:) }

      it "returns empty arrays" do
        result = service.call

        expect(result.previous_charge_ids).to eq([])
        expect(result.previous_charge_filter_ids).to eq([])
      end
    end

    context "when billable metric is not recurring" do
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :sum_agg, field_name: "value", recurring: false) }

      it "returns empty arrays" do
        result = service.call

        expect(result.previous_charge_ids).to eq([])
        expect(result.previous_charge_filter_ids).to eq([])
      end
    end

    context "when organization does not have clickhouse_events_store" do
      let(:organization) { create(:organization, clickhouse_events_store: false, feature_flags: ["enriched_events_aggregation"]) }

      it "returns empty arrays" do
        result = service.call

        expect(result.previous_charge_ids).to eq([])
        expect(result.previous_charge_filter_ids).to eq([])
      end
    end

    context "when organization does not have enriched_events_aggregation flag" do
      let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: []) }

      it "returns empty arrays" do
        result = service.call

        expect(result.previous_charge_ids).to eq([])
        expect(result.previous_charge_filter_ids).to eq([])
      end
    end

    context "when previous plan has no matching charge" do
      before { previous_charge.destroy! }

      it "returns empty arrays" do
        result = service.call

        expect(result.previous_charge_ids).to eq([])
        expect(result.previous_charge_filter_ids).to eq([])
      end
    end
  end
end
