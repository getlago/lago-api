# frozen_string_literal: true

RSpec.describe BillableMetricFilters::DestroyAllService do
  subject(:result) { described_class.call(billable_metric) }

  let(:billable_metric) { create(:billable_metric, :deleted) }
  let(:plan) { create(:plan, organization: billable_metric.organization) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:filters) { create_list(:billable_metric_filter, 2, billable_metric:) }
  let(:charge_filter) { create(:charge_filter, charge:) }
  let(:filter_value) do
    create(:charge_filter_value, charge_filter:, billable_metric_filter: filters.first)
  end

  before { filter_value }

  describe "#call" do
    it "soft deletes all related filters" do
      freeze_time do
        expect { result }.to change { billable_metric.filters.reload.kept.count }.from(2).to(0)
          .and change { filter_value.reload.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "soft deletes the charge filters with a value on a filter of the metric" do
      freeze_time do
        expect { result }.to change { charge_filter.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    context "when the charge filter and its value were updated before" do
      let(:charge_filter) { create(:charge_filter, charge:, updated_at: 3.days.ago) }
      let(:filter_value) do
        create(:charge_filter_value, charge_filter:, billable_metric_filter: filters.first, updated_at: 3.days.ago)
      end

      it "sets their updated_at to the deletion time" do
        freeze_time do
          result

          expect(charge_filter.reload.updated_at).to eq(Time.current)
          expect(ChargeFilterValue.with_discarded.find(filter_value.id).updated_at).to eq(Time.current)
        end
      end
    end

    context "when a charge filter has values on several filters of the metric" do
      let(:other_charge_filter) { create(:charge_filter, charge:) }
      let(:other_billable_metric) { create(:billable_metric, organization: billable_metric.organization) }
      let(:other_metric_charge) { create(:standard_charge, plan:, billable_metric: other_billable_metric) }
      let(:other_metric_filter) { create(:billable_metric_filter, billable_metric: other_billable_metric) }
      let(:other_metric_charge_filter) { create(:charge_filter, charge: other_metric_charge) }

      before do
        create(:charge_filter_value, charge_filter: other_charge_filter, billable_metric_filter: filters.first)
        create(:charge_filter_value, charge_filter: other_charge_filter, billable_metric_filter: filters.second)
        create(:charge_filter_value, charge_filter: other_metric_charge_filter, billable_metric_filter: other_metric_filter)
      end

      it "soft deletes it and keeps the charge filters of other metrics" do
        freeze_time do
          result

          expect(other_charge_filter.reload.deleted_at).to eq(Time.current)
          expect(other_metric_charge_filter.reload.deleted_at).to be_nil
        end
      end
    end

    context "when the charge filter is already deleted" do
      let(:original_deleted_at) { 2.days.ago.change(usec: 0) }
      let(:original_updated_at) { 3.days.ago.change(usec: 0) }
      let(:charge_filter) do
        create(:charge_filter, charge:, deleted_at: original_deleted_at, updated_at: original_updated_at)
      end
      let(:kept_charge_filter) { create(:charge_filter, charge:) }

      before do
        create(:charge_filter_value, charge_filter: kept_charge_filter, billable_metric_filter: filters.first)
      end

      it "keeps its original deletion date and soft deletes the kept charge filter" do
        freeze_time do
          result

          deleted_charge_filter = ChargeFilter.with_discarded.find(charge_filter.id)
          expect(deleted_charge_filter.deleted_at).to eq(original_deleted_at)
          expect(deleted_charge_filter.updated_at).to eq(original_updated_at)
          expect(kept_charge_filter.reload.deleted_at).to eq(Time.current)
        end
      end
    end

    context "when the charge filter values were already deleted by a previous run" do
      let(:filter_value) do
        create(:charge_filter_value, charge_filter:, billable_metric_filter: filters.first, deleted_at: 1.day.ago)
      end

      it "soft deletes the charge filter" do
        freeze_time do
          expect { result }.to change { charge_filter.reload.deleted_at }.from(nil).to(Time.current)
        end
      end
    end

    context "when the billable metric is not deleted" do
      let(:billable_metric) { create(:billable_metric) }

      it "does not delete the filters" do
        expect { result }.not_to change { billable_metric.filters.reload.kept.count }
        expect(charge_filter.reload.deleted_at).to be_nil
      end
    end

    context "when the billable metric is nil" do
      let(:billable_metric) { nil }
      let(:filter_value) { nil }

      it "returns an empty result" do
        expect(result).to be_success
        expect(result.billable_metric).to be_nil
      end
    end
  end
end
