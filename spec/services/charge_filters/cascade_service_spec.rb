# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::CascadeService do
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:bm_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }
  let(:parent_plan) { create(:plan, organization:) }
  let(:parent_charge) { create(:standard_charge, plan: parent_plan, billable_metric:, properties: {amount: "0"}) }

  let(:child_plan) { create(:plan, organization:, parent: parent_plan) }
  let(:child_charge) { create(:standard_charge, plan: child_plan, billable_metric:, parent: parent_charge, properties: {amount: "0"}) }
  let!(:subscription) { create(:subscription, plan: child_plan, status: :active) }

  let!(:parent_filter) do
    filter = create(:charge_filter, charge: parent_charge, invoice_display_name: "US region", properties: {amount: "10"})
    create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["us"])
    filter
  end

  let!(:child_filter) do
    filter = create(:charge_filter, charge: child_charge, invoice_display_name: "US region", properties: {amount: "10"})
    create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["us"])
    filter
  end

  describe "#call" do
    context "with update action" do
      subject(:service) do
        described_class.call(
          charge: parent_charge,
          action: "update",
          filter_values: {"region" => ["us"]},
          old_properties: {"amount" => "10"},
          new_properties: {"amount" => "15"},
          invoice_display_name: "US region updated"
        )
      end

      it "updates the matching child filter" do
        service

        expect(child_filter.reload).to have_attributes(
          properties: {"amount" => "15"},
          invoice_display_name: "US region updated"
        )
      end

      context "when child filter was customized" do
        let!(:child_filter) do
          filter = create(:charge_filter, charge: child_charge, invoice_display_name: "Custom", properties: {amount: "99"})
          create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values: ["us"])
          filter
        end

        it "does not update the customized filter properties" do
          service

          expect(child_filter.reload.properties).to eq({"amount" => "99"})
        end
      end

      context "when child has no matching filter" do
        let!(:child_filter) { nil }

        it "succeeds without error" do
          expect(service).to be_success
        end
      end
    end

    context "with create action" do
      subject(:service) do
        described_class.call(
          charge: parent_charge,
          action: "create",
          filter_values: {"region" => ["eu"]},
          new_properties: {"amount" => "20"},
          invoice_display_name: "EU region"
        )
      end

      let!(:eu_bm_filter) { bm_filter } # reuse — already has "eu" in values

      it "creates the filter on the child charge" do
        expect { service }.to change { child_charge.filters.reload.count }.by(1)

        new_filter = child_charge.filters.find_by(invoice_display_name: "EU region")
        expect(new_filter.properties).to eq({"amount" => "20"})
        expect(new_filter.to_h).to eq({"region" => ["eu"]})
      end

      context "when child already has the filter" do
        before do
          existing = create(:charge_filter, charge: child_charge, properties: {amount: "20"})
          create(:charge_filter_value, charge_filter: existing, billable_metric_filter: bm_filter, values: ["eu"])
        end

        it "does not create a duplicate" do
          expect { service }.not_to change { child_charge.filters.reload.count }
        end
      end
    end

    context "with destroy action" do
      subject(:service) do
        described_class.call(
          charge: parent_charge,
          action: "destroy",
          filter_values: {"region" => ["us"]}
        )
      end

      it "discards the matching child filter and its values" do
        service

        expect(child_filter.reload).to be_discarded
        expect(child_filter.values.kept).to be_empty
      end

      context "when child has no matching filter" do
        let!(:child_filter) { nil }

        it "succeeds without error" do
          expect(service).to be_success
        end
      end
    end

    context "when child charge has no active subscription" do
      let!(:subscription) { create(:subscription, plan: child_plan, status: :terminated) }

      subject(:service) do
        described_class.call(
          charge: parent_charge,
          action: "update",
          filter_values: {"region" => ["us"]},
          old_properties: {"amount" => "10"},
          new_properties: {"amount" => "15"},
          invoice_display_name: "US region"
        )
      end

      it "does not update the child filter" do
        service

        expect(child_filter.reload.properties).to eq({"amount" => "10"})
      end
    end
  end
end
