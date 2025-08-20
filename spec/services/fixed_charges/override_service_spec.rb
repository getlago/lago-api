# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::OverrideService, type: :service do
  subject(:override_service) { described_class.new(fixed_charge:, params:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:tax) { create(:tax, organization:) }

  let(:fixed_charge) do
    create(
      :fixed_charge,
      organization:,
      plan:,
      add_on:,
      properties: {amount: "300"},
      invoice_display_name: "Original Display Name",
      units: 5
    )
  end

  let(:params) do
    {
      properties: {amount: "200"},
      invoice_display_name: "Overridden Display Name",
      units: 10,
      tax_codes: [tax.code]
    }
  end

  describe "#call" do
    before { fixed_charge }

    context "when lago freemium" do
      it "returns without overriding the fixed charge" do
        expect { override_service.call }.not_to change(FixedCharge, :count)
      end
    end

    context "when lago premium" do
      around { |test| lago_premium!(&test) }

      it "creates a fixed charge based on the given fixed charge" do
        expect { override_service.call }.to change(FixedCharge, :count).by(1)

        new_fixed_charge = FixedCharge.order(:created_at).last
        expect(new_fixed_charge).to have_attributes(
          organization_id: organization.id,
          plan_id: plan.id,
          add_on_id: add_on.id,
          charge_model: fixed_charge.charge_model,
          pay_in_advance: fixed_charge.pay_in_advance,
          prorated: fixed_charge.prorated,
          # Parent id
          parent_id: fixed_charge.id,
          # Overridden attributes
          properties: {"amount" => "200"},
          invoice_display_name: "Overridden Display Name",
          units: 10
        )
        expect(new_fixed_charge.taxes).to contain_exactly(tax)
      end

      context "when only properties are provided" do
        let(:params) { {properties: {amount: "150"}} }

        it "creates a fixed charge with only properties overridden" do
          expect { override_service.call }.to change(FixedCharge, :count).by(1)

          new_fixed_charge = FixedCharge.order(:created_at).last
          expect(new_fixed_charge).to have_attributes(
            parent_id: fixed_charge.id,
            properties: {"amount" => "150"},
            invoice_display_name: fixed_charge.invoice_display_name,
            units: fixed_charge.units
          )
        end
      end

      context "when only invoice_display_name is provided" do
        let(:params) { {invoice_display_name: "Custom Display Name"} }

        it "creates a fixed charge with only invoice_display_name overridden" do
          expect { override_service.call }.to change(FixedCharge, :count).by(1)

          new_fixed_charge = FixedCharge.order(:created_at).last
          expect(new_fixed_charge).to have_attributes(
            parent_id: fixed_charge.id,
            properties: fixed_charge.properties,
            invoice_display_name: "Custom Display Name",
            units: fixed_charge.units
          )
        end
      end

      context "when tax_codes are provided" do
        let(:tax2) { create(:tax, organization:, code: "tax2") }
        let(:params) { {tax_codes: [tax.code, tax2.code]} }

        before { tax2 }

        it "applies taxes to the new fixed charge" do
          expect { override_service.call }.to change(FixedCharge, :count).by(1)

          new_fixed_charge = FixedCharge.order(:created_at).last
          expect(new_fixed_charge.taxes).to contain_exactly(tax, tax2)
        end
      end

      context "when no params are provided" do
        let(:params) { {} }

        it "creates a fixed charge with no overrides" do
          expect { override_service.call }.to change(FixedCharge, :count).by(1)

          new_fixed_charge = FixedCharge.order(:created_at).last
          expect(new_fixed_charge).to have_attributes(
            parent_id: fixed_charge.id,
            properties: fixed_charge.properties,
            invoice_display_name: fixed_charge.invoice_display_name,
            units: fixed_charge.units
          )
        end
      end

      context "when fixed charge has existing taxes" do
        let(:existing_tax) { create(:tax, organization:, code: "existing_tax") }

        before do
          create(:fixed_charge_applied_tax, fixed_charge:, tax: existing_tax)
        end

        it "replaces existing taxes with new ones" do
          expect { override_service.call }.to change(FixedCharge, :count).by(1)

          new_fixed_charge = FixedCharge.order(:created_at).last
          expect(new_fixed_charge.taxes).to contain_exactly(tax)
          expect(new_fixed_charge.taxes).not_to include(existing_tax)
        end
      end

      context "when validation fails" do
        let(:params) { {units: -1} }

        it "returns a validation failure" do
          result = override_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect { override_service.call }.not_to change(FixedCharge, :count)
        end
      end

      context "when tax is not found" do
        let(:params) { {tax_codes: ["non_existent_tax"]} }

        it "returns a failure" do
          result = override_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect { override_service.call }.not_to change(FixedCharge, :count)
        end
      end

      context "when fixed charge is being overridden with a different charge model" do
        let(:fixed_charge) do
          create(
            :fixed_charge,
            :graduated,
            organization:,
            plan:,
            add_on:,
            properties: {
              graduated_ranges: [
                {from_value: 0, to_value: 10, per_unit_amount: "5", flat_amount: "200"},
                {from_value: 11, to_value: nil, per_unit_amount: "1", flat_amount: "300"}
              ]
            }
          )
        end
        let(:params) do
          {
            charge_model: "standard",
            properties: {amount: "200"},
            invoice_display_name: "Overridden Display Name",
            units: 10,
            tax_codes: [tax.code]
          }
        end

        it "raises a forbidden error" do
          result = override_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("cannot_override_charge_model")
        end
      end

      context "when override properties are invalid" do
        let(:fixed_charge) do
          create(
            :fixed_charge,
            :graduated,
            organization:,
            plan:,
            add_on:,
            properties: {
              graduated_ranges: [
                {from_value: 0, to_value: 10, per_unit_amount: "5", flat_amount: "200"},
                {from_value: 11, to_value: nil, per_unit_amount: "1", flat_amount: "300"}
              ]
            }
          )
        end
        let(:params) { {properties: {amount: 100}} }

        it "returns a validation failure" do
          result = override_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:fixed_charge]).to eq(["invalid_properties"])
        end
      end
    end
  end
end 