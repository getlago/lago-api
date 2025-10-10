# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::UpdateService do
  subject(:update_service) { described_class.new(fixed_charge:, params:, cascade_options:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }

  let(:fixed_charge) do
    create(:fixed_charge, plan:, add_on:, prorated: false, pay_in_advance: false, units: 10)
  end

  let(:cascade_options) { {cascade: false} }
  let(:params) do
    {
      charge_model: "standard",
      invoice_display_name: "Updated Display Name",
      units: 5,
      prorated: true,
      pay_in_advance: true,
      properties: {amount: "200"}
    }
  end

  describe "#call" do
    subject(:result) { update_service.call }

    context "when fixed_charge is missing" do
      let(:fixed_charge) { nil }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("fixed_charge_not_found")
      end
    end

    context "when fixed_charge exists" do
      it "updates the fixed charge without updating pay_in_advance and prorated" do
        expect(result).to be_success
        expect(result.fixed_charge).to have_attributes(
          charge_model: "standard",
          invoice_display_name: "Updated Display Name",
          units: 5,
          prorated: false,
          pay_in_advance: false,
          properties: {"amount" => "200"}
        )
      end

      context "when plan is attached to subscriptions" do
        before do
          create(:subscription, plan:)
        end

        it "does not update charge_model" do
          original_charge_model = fixed_charge.charge_model
          params[:charge_model] = "graduated"

          expect(result).to be_success
          expect(result.fixed_charge.charge_model).to eq(original_charge_model)
        end

        it "does not apply taxes" do
          tax = create(:tax, organization: plan.organization, code: "tax1")
          params[:tax_codes] = [tax.code]

          expect(result).to be_success
          expect(fixed_charge.reload.applied_taxes).to be_empty
        end
      end

      context "when plan is not attached to subscriptions" do
        it "updates charge_model" do
          params[:charge_model] = "graduated"
          params[:properties] = {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: nil,
                per_unit_amount: "10",
                flat_amount: "0"
              }
            ]
          }

          expect(result).to be_success
          expect(result.fixed_charge.charge_model).to eq("graduated")
        end

        context "when tax_codes are provided" do
          let(:tax1) { create(:tax, organization: plan.organization, code: "tax1") }
          let(:tax2) { create(:tax, organization: plan.organization, code: "tax2") }

          before do
            params[:tax_codes] = [tax1.code, tax2.code]
          end

          it "applies taxes to the fixed charge" do
            expect { result }.to change { fixed_charge.reload.applied_taxes.count }.from(0).to(2)
          end

          it "returns success" do
            expect(result).to be_success
          end
        end
      end

      context "when properties are not provided" do
        let(:params) do
          {
            charge_model: "standard",
            invoice_display_name: "Updated Display Name",
            units: 5,
            prorated: true
          }
        end

        it "uses default properties for the charge model" do
          expect(result).to be_success
          expect(result.fixed_charge.properties).to eq({"amount" => "0"})
        end
      end

      context "when cascade is true" do
        let(:cascade_options) { {cascade: true} }

        context "when charge_model is different" do
          before do
            params[:charge_model] = "graduated"
          end

          it "returns early without updating" do
            expect(result).to be_success
            expect(result.fixed_charge).to be_nil
          end
        end

        context "when charge_model is the same" do
          it "does not update the display name" do
            expect(result).to be_success
            expect(result.fixed_charge.invoice_display_name).not_to eq("Updated Display Name")
          end

          context "when equal_properties is true" do
            let(:cascade_options) { {cascade: true, equal_properties: true} }

            it "updates properties" do
              expect(result).to be_success
              expect(result.fixed_charge.properties).to eq({"amount" => "200"})
            end
          end

          context "when equal_properties is false" do
            it "does not update properties" do
              original_properties = fixed_charge.properties
              expect(result).to be_success
              expect(result.fixed_charge.properties).to eq(original_properties)
            end
          end
        end

        it "does not apply taxes" do
          tax = create(:tax, organization: plan.organization, code: "tax1")
          params[:tax_codes] = [tax.code]

          expect(result).to be_success
          expect(fixed_charge.reload.applied_taxes).to be_empty
        end
      end

      context "with validation errors" do
        let(:params) do
          {
            charge_model: "standard",
            units: -1 # Invalid units
          }
        end

        it "returns a validation failure" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
        end
      end

      context "when tax service fails" do
        let(:params) do
          {
            charge_model: "standard",
            invoice_display_name: "Updated Display Name",
            units: 5,
            prorated: true,
            properties: {amount: "200"},
            tax_codes: ["non_existent_tax"]
          }
        end

        it "returns the tax service error" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq("tax_not_found")
        end
      end

      context "when units have been changed" do
        let(:params) do
          {
            charge_model: "standard",
            apply_units_immediately: true,
            units: fixed_charge.units + 15,
            properties: {amount: "200"}
          }
        end

        before do
          allow(FixedCharges::EmitEventsForActiveSubscriptionsService)
            .to receive(:call!)
        end

        it "emits fixed charge events for all active subscriptions" do
          result

          expect(FixedCharges::EmitEventsForActiveSubscriptionsService)
            .to have_received(:call!)
            .with(
              fixed_charge: result.fixed_charge,
              apply_units_immediately: true
            )
            .once
        end

        context "when apply_units_immediately is false" do
          let(:params) do
            {
              charge_model: "standard",
              apply_units_immediately: false,
              units: fixed_charge.units + 15,
              properties: {amount: "200"}
            }
          end

          it "emits fixed charge events for all active subscriptions" do
            result

            expect(FixedCharges::EmitEventsForActiveSubscriptionsService)
              .to have_received(:call!)
              .with(
                fixed_charge: result.fixed_charge,
                apply_units_immediately: false
              )
              .once
          end
        end
      end

      context "when units does not change" do
        let(:params) do
          {
            charge_model: "standard",
            apply_units_immediately: true,
            units: fixed_charge.units,
            properties: {amount: "200"}
          }
        end

        before do
          allow(FixedCharges::EmitEventsForActiveSubscriptionsService)
            .to receive(:call!)
        end

        it "does not emit any fixed charge events" do
          result

          expect(FixedCharges::EmitEventsForActiveSubscriptionsService)
            .not_to have_received(:call!)
        end
      end
    end
  end
end
