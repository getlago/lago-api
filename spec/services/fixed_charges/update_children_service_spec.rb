# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::UpdateChildrenService do
  subject(:update_service) do
    described_class.new(fixed_charge:, params:, old_parent_attrs:, child_ids:, timestamp:)
  end

  let(:organization) { create(:organization) }
  let(:add_on) { create(:add_on, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:child_plan) { create(:plan, organization:, parent: plan) }
  let(:timestamp) { Time.current.to_i }

  let(:params) do
    {
      charge_model: "standard",
      properties: {amount: "200"},
      units: 1
    }
  end

  describe "#call" do
    context "when fixed_charge is not found" do
      let(:fixed_charge) { nil }
      let(:old_parent_attrs) { {} }
      let(:child_ids) { [] }

      it "returns success without processing" do
        result = update_service.call

        expect(result).to be_success
        expect(result.fixed_charge).to be_nil
      end
    end

    context "when child fixed charges are successfully updated" do
      let(:fixed_charge) do
        create(:fixed_charge, organization:, plan:, add_on:, properties: {amount: "100"})
      end

      let(:child_fixed_charge) do
        create(
          :fixed_charge,
          organization:,
          plan: child_plan,
          add_on:,
          parent: fixed_charge,
          properties: {amount: "100"}
        )
      end

      let(:child_ids) { [child_fixed_charge.id] }
      let(:old_parent_attrs) { fixed_charge.attributes }

      before { child_fixed_charge }

      it "updates child fixed charges" do
        expect { update_service.call }.to change { child_fixed_charge.reload.properties }
          .from({"amount" => "100"})
          .to({"amount" => "200"})
      end

      it "does not touch plan" do
        freeze_time do
          expect { update_service.call }.not_to change { child_plan.reload.updated_at }
        end
      end

      it "returns success result with fixed charge" do
        result = update_service.call

        expect(result).to be_success
        expect(result.fixed_charge).to eq(fixed_charge)
      end

      context "when properties are different" do
        before do
          child_fixed_charge.update!(properties: {amount: "300"})
        end

        it "does not update child properties when they differ" do
          expect { update_service.call }.not_to change { child_fixed_charge.reload.properties }
        end
      end
    end

    context "with multiple child fixed charges" do
      let(:fixed_charge) do
        create(:fixed_charge, organization:, plan:, add_on:, properties: {amount: "100"})
      end

      let(:child_fixed_charge_1) do
        create(
          :fixed_charge,
          organization:,
          plan: child_plan,
          add_on:,
          parent: fixed_charge,
          properties: {amount: "100"}
        )
      end

      let(:child_fixed_charge_2) do
        create(
          :fixed_charge,
          organization:,
          plan: child_plan,
          add_on:,
          parent: fixed_charge,
          properties: {amount: "100"}
        )
      end

      let(:child_ids) { [child_fixed_charge_1.id, child_fixed_charge_2.id] }
      let(:old_parent_attrs) { fixed_charge.attributes }

      before do
        child_fixed_charge_1
        child_fixed_charge_2
      end

      it "updates all specified child fixed charges" do
        update_service.call

        expect(child_fixed_charge_1.reload.properties).to eq({"amount" => "200"})
        expect(child_fixed_charge_2.reload.properties).to eq({"amount" => "200"})
      end
    end

    context "when triggering pay-in-advance billing" do
      let(:fixed_charge) do
        create(:fixed_charge, organization:, plan:, add_on:, units: 10, pay_in_advance: true, properties: {amount: "100"})
      end

      let(:child_fixed_charge) do
        create(
          :fixed_charge,
          organization:,
          plan: child_plan,
          add_on:,
          parent: fixed_charge,
          units: 10,
          pay_in_advance: true,
          properties: {amount: "100"}
        )
      end

      let(:child_subscription) { create(:subscription, plan: child_plan) }
      let(:child_ids) { [child_fixed_charge.id] }
      let(:old_parent_attrs) { fixed_charge.attributes }

      before do
        child_fixed_charge
        child_subscription
        allow(Invoices::CreatePayInAdvanceFixedChargesJob).to receive(:perform_later)
      end

      context "when apply_units_immediately is true and fixed charge is pay_in_advance" do
        let(:params) do
          {
            charge_model: "standard",
            properties: {amount: "200"},
            units: 15,
            apply_units_immediately: true
          }
        end

        it "triggers billing for child subscription" do
          update_service.call

          expect(Invoices::CreatePayInAdvanceFixedChargesJob).to have_received(:perform_later)
            .with(child_subscription, timestamp)
        end
      end

      context "when apply_units_immediately is false" do
        let(:params) do
          {
            charge_model: "standard",
            properties: {amount: "200"},
            units: 15,
            apply_units_immediately: false
          }
        end

        it "does not trigger billing" do
          update_service.call

          expect(Invoices::CreatePayInAdvanceFixedChargesJob).not_to have_received(:perform_later)
        end
      end

      context "when fixed charge is not pay_in_advance" do
        let(:fixed_charge) do
          create(:fixed_charge, organization:, plan:, add_on:, units: 10, pay_in_advance: false, properties: {amount: "100"})
        end

        let(:child_fixed_charge) do
          create(
            :fixed_charge,
            organization:,
            plan: child_plan,
            add_on:,
            parent: fixed_charge,
            units: 10,
            pay_in_advance: false,
            properties: {amount: "100"}
          )
        end

        let(:params) do
          {
            charge_model: "standard",
            properties: {amount: "200"},
            units: 15,
            apply_units_immediately: true
          }
        end

        it "does not trigger billing" do
          update_service.call

          expect(Invoices::CreatePayInAdvanceFixedChargesJob).not_to have_received(:perform_later)
        end
      end
    end
  end
end
