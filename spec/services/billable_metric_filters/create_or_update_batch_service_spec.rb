# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetricFilters::CreateOrUpdateBatchService do
  subject(:service) { described_class.call(billable_metric:, filters_params:) }

  let(:billable_metric) { create(:billable_metric) }

  context "when filter params is empty" do
    let(:filters_params) { {} }

    it "does not create any filters" do
      expect { service }.not_to change(BillableMetricFilter, :count)
    end

    context "when there are existing filters" do
      let(:filter) { create(:billable_metric_filter, billable_metric:) }

      let(:charge) { create(:standard_charge, billable_metric:) }
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:filter_value) do
        create(
          :charge_filter_value,
          charge_filter:,
          billable_metric_filter: filter,
          values: [filter.values.first]
        )
      end

      before { filter_value }

      it "discards all filters and the related values" do
        expect { service }.to change { filter.reload.discarded? }.to(true)
          .and change { filter_value.reload.discarded? }.to(true)
          .and change { charge_filter.reload.discarded? }.to(true)
      end
    end
  end

  context "with new filters" do
    let(:filters_params) do
      [
        {
          key: "region",
          values: %w[Europe US]
        },
        {
          key: "cloud",
          values: %w[aws gcp]
        }
      ]
    end

    it "creates the filters" do
      expect { service }.to change(BillableMetricFilter, :count).by(2)

      filter1 = billable_metric.filters.find_by(key: "region")
      expect(filter1).to have_attributes(
        key: "region",
        values: %w[Europe US]
      )

      filter2 = billable_metric.filters.find_by(key: "cloud")
      expect(filter2).to have_attributes(
        key: "cloud",
        values: %w[aws gcp]
      )
    end
  end

  context "with existing filters" do
    let(:filters_params) do
      [
        {
          key: "region",
          values: %w[Europe US Asia Africa]
        }
      ]
    end

    let(:filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[Europe US Asia]) }

    before { filter }

    it "updates the filters" do
      expect { service }.not_to change(BillableMetricFilter, :count)

      expect(filter.reload).to have_attributes(
        key: "region",
        values: %w[Europe US Asia Africa]
      )
    end

    context "when a value is removed" do
      let(:filters_params) do
        [
          {
            key: "region",
            values: %w[Europe]
          }
        ]
      end

      let!(:filter_value) do
        create(
          :charge_filter_value,
          billable_metric_filter: filter,
          values: ["US"]
        )
      end

      it "discards the removed value" do
        expect { service }.not_to change(BillableMetricFilter, :count)

        expect(filter.reload).to have_attributes(
          key: "region",
          values: %w[Europe]
        )

        expect(filter_value.reload).to be_discarded
      end

      context "when removing all values" do
        let(:filters_params) do
          []
        end

        let(:charge) { create(:standard_charge, billable_metric:) }
        let(:charge_filter) { create(:charge_filter, charge:) }

        before do
          create(
            :charge_filter_value,
            charge_filter:,
            billable_metric_filter: filter,
            values: ["US"]
          )

          create(
            :charge_filter_value,
            charge_filter:,
            billable_metric_filter: filter,
            values: ["Europe"]
          )
        end

        it "discards the removed value" do
          expect { service }.to change(BillableMetricFilter, :count).by(-1)

          expect(filter.reload).to be_discarded
          expect(filter.filter_values.with_discarded).to all(be_discarded)
        end
      end
    end

    context "when a filter is removed" do
      let(:filters_params) do
        [
          {
            key: "country",
            values: %w[USA France Germany]
          }
        ]
      end

      it "discards the removed filter" do
        expect { service }.not_to change(BillableMetricFilter, :count)

        expect(filter.reload).to be_discarded
      end
    end
  end
end
