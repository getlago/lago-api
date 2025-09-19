# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateChildrenService do
  subject(:update_service) do
    described_class.new(
      charge:,
      params:,
      old_parent_attrs:,
      old_parent_filters_attrs:,
      old_parent_applied_pricing_unit_attrs:,
      child_ids:
    )
  end

  let(:billable_metric) { create(:billable_metric) }
  let(:organization) { billable_metric.organization }
  let(:plan) { create(:plan, organization:) }
  let(:old_parent_attrs) { charge&.attributes }
  let(:old_parent_filters_attrs) { charge&.filters&.map(&:attributes) }
  let(:old_parent_applied_pricing_unit_attrs) { charge&.applied_pricing_unit&.attributes }
  let(:charge) do
    create(
      :standard_charge,
      plan:,
      billable_metric:,
      amount_currency: "USD",
      properties: {
        amount: "300"
      }
    )
  end
  let(:billable_metric_filter) do
    create(
      :billable_metric_filter,
      billable_metric:,
      key: "payment_method",
      values: %w[card physical]
    )
  end

  let(:child_plan) { create(:plan, organization:, parent_id:) }
  let(:parent_id) { plan.id }
  let(:charge_parent_id) { charge.id }
  let(:child_ids) { [child_charge&.id] }
  let(:child_charge) do
    create(
      :standard_charge,
      plan_id: child_plan.id,
      parent_id: charge_parent_id,
      billable_metric_id: billable_metric.id,
      properties: {amount: "300"}
    )
  end
  let(:params) do
    {
      id: charge&.id,
      billable_metric_id: billable_metric.id,
      charge_model: "standard",
      pay_in_advance: true,
      prorated: true,
      invoiceable: false,
      properties: {
        amount: "400"
      },
      applied_pricing_unit: {conversion_rate: 2.5},
      filters: [
        {
          invoice_display_name: "Card filter",
          properties: {amount: "90"},
          values: {billable_metric_filter.key => ["card"]}
        }
      ]
    }
  end

  before do
    charge && create(:applied_pricing_unit, pricing_unitable: charge, conversion_rate: 1.1)
    child_charge && create(:applied_pricing_unit, pricing_unitable: child_charge, conversion_rate: 1.1)
  end

  describe "#call" do
    context "when charge is not found" do
      let(:charge) { nil }
      let(:child_charge) { nil }

      it "returns an empty result" do
        result = update_service.call

        expect(result).to be_success
        expect(result.charge).to be_nil
      end
    end

    context "when charge has children that has not been modified" do
      it "updates child charge" do
        update_service.call

        expect(child_charge.reload).to have_attributes(
          properties: {"amount" => "400"}
        )

        expect(child_charge.filters.first).to have_attributes(
          invoice_display_name: "Card filter",
          properties: {"amount" => "90"}
        )
        expect(child_charge.filters.first.values.first).to have_attributes(
          billable_metric_filter_id: billable_metric_filter.id,
          values: ["card"]
        )
        expect(child_charge.applied_pricing_unit.conversion_rate).to eq 2.5
      end

      it "does not touch plan" do
        freeze_time do
          expect { update_service.call }.not_to change { child_plan.reload.updated_at }
        end
      end
    end

    context "when charge has children that has been modified" do
      let(:child_charge) do
        create(
          :standard_charge,
          plan_id: child_plan.id,
          parent_id: charge_parent_id,
          billable_metric_id: billable_metric.id,
          properties: {amount: "500"}
        )
      end

      it "does not update charge properties" do
        update_service.call

        expect(child_charge.reload).to have_attributes(
          properties: {"amount" => "500"}
        )
      end
    end

    context "when charge has no children" do
      let(:child_charge) do
        create(
          :standard_charge,
          plan_id: child_plan.id,
          parent_id: nil,
          billable_metric_id: billable_metric.id,
          properties: {amount: "300"}
        )
      end

      before do
        allow(Charges::UpdateService).to receive(:call!).and_call_original
      end

      it "does not call the update service" do
        update_service.call

        expect(Charges::UpdateService).not_to have_received(:call!)
      end

      it "does not update charge properties" do
        update_service.call

        expect(child_charge.reload).to have_attributes(
          properties: {"amount" => "300"}
        )
      end
    end
  end
end
