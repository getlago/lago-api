# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateChildrenService do
  subject(:service) do
    described_class.new(
      params:,
      old_parent_attrs:,
      old_parent_filters_attrs:,
      old_parent_applied_pricing_unit_attrs:
    )
  end

  let(:billable_metric) { create(:billable_metric) }
  let(:organization) { billable_metric.organization }
  let(:plan) { create(:plan, organization:) }
  let(:charge) do
    create(
      :standard_charge,
      plan:,
      billable_metric:,
      properties: {amount: "300"}
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

  let(:child_plan) { create(:plan, organization:, parent_id: plan.id) }
  let(:child_charge) do
    create(
      :standard_charge,
      plan: child_plan,
      parent_id: charge.id,
      billable_metric:,
      properties: {amount: "300"}
    )
  end
  let(:old_parent_attrs) { charge.attributes }
  let(:old_parent_filters_attrs) { charge.filters.map(&:attributes) }
  let(:old_parent_applied_pricing_unit_attrs) { charge.applied_pricing_unit&.attributes }
  let(:params) do
    {
      charge_model: "standard",
      properties: {amount: "400"},
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
    create(:subscription, plan: child_plan)
    charge && create(:applied_pricing_unit, pricing_unitable: charge, conversion_rate: 1.1)
    child_charge && create(:applied_pricing_unit, pricing_unitable: child_charge, conversion_rate: 1.1)
  end

  describe "#call" do
    it "updates child charges with active subscriptions" do
      service.call

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
        expect { service.call }.not_to change { child_plan.reload.updated_at }
      end
    end

    it "does not issue an extra child charge update from filter saves" do
      child_charge_updates = []

      callback = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql]
        next unless sql.match?(/\AUPDATE\s+"charges"/i)

        binds = payload[:type_casted_binds] || payload[:binds]
        next unless Array(binds).include?(child_charge.id)

        child_charge_updates << sql
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        service.call
      end

      expect(child_charge_updates.size).to eq(1)
    end

    context "when child charge properties have been modified" do
      let(:child_charge) do
        create(
          :standard_charge,
          plan: child_plan,
          parent_id: charge.id,
          billable_metric:,
          properties: {amount: "500"}
        )
      end

      it "does not overwrite modified properties" do
        service.call

        expect(child_charge.reload).to have_attributes(
          properties: {"amount" => "500"}
        )
      end
    end

    context "when child has a terminated subscription" do
      let(:child_plan2) { create(:plan, organization:, parent_id: plan.id) }
      let!(:child_charge2) do
        create(
          :standard_charge,
          plan: child_plan2,
          parent_id: charge.id,
          billable_metric:,
          properties: {amount: "300"}
        )
      end

      before { create(:subscription, plan: child_plan2, status: :terminated) }

      it "skips children without active or pending subscriptions" do
        service.call

        expect(child_charge2.reload).to have_attributes(
          properties: {"amount" => "300"}
        )
      end
    end

    context "when charge is not found" do
      let(:old_parent_attrs) { {"id" => SecureRandom.uuid} }

      before do
        allow(Charges::UpdateService).to receive(:call!)
      end

      it "returns early without processing" do
        service.call

        expect(Charges::UpdateService).not_to have_received(:call!)
      end
    end
  end
end
