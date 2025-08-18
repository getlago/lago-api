# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::CreateChildrenService, type: :service do
  subject(:create_service) { described_class.new(child_ids:, fixed_charge:, payload:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, organization:, plan:, add_on:) }

  let(:child_plan) { create(:plan, organization:, parent_id:) }
  let(:parent_id) { plan.id }
  let(:child_ids) { child_plan.id }

  let(:payload) { {} }

  before do
    fixed_charge
    child_plan
  end

  describe "#call" do
    context "when fixed_charge is not found" do
      let(:fixed_charge) { nil }

      it "returns an error" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("fixed_charge_not_found")
      end
    end

    context "when child fixed charge is successfully added" do
      let(:payload) do
        {
          add_on_id: add_on.id,
          charge_model: "standard",
          pay_in_advance: false,
          prorated: false,
          units: 5,
          invoice_display_name: "Child Fixed Charge",
          properties: {amount: "100"}
        }
      end

      it "creates new fixed charge" do
        expect { create_service.call }.to change(FixedCharge, :count).by(1)
      end

      it "does not touch plan" do
        freeze_time do
          expect { create_service.call }.not_to change { child_plan.reload.updated_at }
        end
      end

      it "sets correctly attributes" do
        create_service.call

        stored_fixed_charge = child_plan.reload.fixed_charges.first

        expect(stored_fixed_charge).to have_attributes(
          organization_id: organization.id,
          add_on_id: add_on.id,
          charge_model: "standard",
          pay_in_advance: false,
          prorated: false,
          units: 5,
          invoice_display_name: "Child Fixed Charge",
          parent_id: fixed_charge.id,
          properties: {"amount" => "100"}
        )
      end

      it "returns success result" do
        result = create_service.call

        expect(result).to be_success
        expect(result.fixed_charge).to eq(fixed_charge)
      end
    end
  end
end
