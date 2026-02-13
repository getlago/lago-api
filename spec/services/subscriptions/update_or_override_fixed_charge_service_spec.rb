# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::UpdateOrOverrideFixedChargeService do
  subject(:service) { described_class.new(subscription:, fixed_charge:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, organization:, add_on:) }
  let(:params) do
    {
      invoice_display_name: "Overridden Fixed Charge",
      units: "10"
    }
  end

  describe "#call" do
    context "without premium license" do
      it "returns forbidden failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end

    context "with premium license", :premium do
      before do
        fixed_charge
        subscription
      end

      it "creates a plan override" do
        expect { service.call }.to change(Plan, :count).by(1)

        new_plan = subscription.reload.plan
        expect(new_plan.parent_id).to eq(plan.id)
      end

      it "creates fixed charge override via plan override" do
        expect { service.call }.to change(FixedCharge, :count).by(1)
      end

      it "returns the fixed charge override with parent_id" do
        result = service.call

        expect(result.fixed_charge.parent_id).to eq(fixed_charge.id)
      end

      it "assigns the fixed charge override to the new plan" do
        result = service.call

        expect(result.fixed_charge.plan_id).not_to eq(plan.id)
        expect(result.fixed_charge.plan.parent_id).to eq(plan.id)
      end

      it "updates the subscription to use the overridden plan" do
        service.call

        subscription.reload
        expect(subscription.plan.parent_id).to eq(plan.id)
      end

      it "applies the override params to the fixed charge" do
        result = service.call

        expect(result.fixed_charge.invoice_display_name).to eq("Overridden Fixed Charge")
        expect(result.fixed_charge.units).to eq(10)
      end

      context "when subscription is nil" do
        let(:subscription) { nil }

        it "returns not found failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("subscription")
        end
      end

      context "when fixed_charge is nil" do
        let(:fixed_charge) { nil }

        it "returns not found failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("fixed_charge")
        end
      end

      context "when subscription already has a plan override" do
        let(:overridden_plan) { create(:plan, organization:, parent: plan) }
        let(:subscription) { create(:subscription, customer:, plan: overridden_plan) }

        it "does not create a new plan" do
          expect { service.call }.not_to change(Plan, :count)
        end

        it "creates the fixed charge override on the existing overridden plan" do
          result = service.call

          expect(result.fixed_charge.plan_id).to eq(overridden_plan.id)
          expect(result.fixed_charge.parent_id).to eq(fixed_charge.id)
        end
      end

      context "when fixed charge override already exists" do
        let(:overridden_plan) { create(:plan, organization:, parent: plan) }
        let(:subscription) { create(:subscription, customer:, plan: overridden_plan) }
        let!(:existing_override) { create(:fixed_charge, plan: overridden_plan, organization:, add_on:, parent: fixed_charge, code: fixed_charge.code) }

        it "does not create a new fixed charge" do
          expect { service.call }.not_to change(FixedCharge, :count)
        end

        it "updates the existing fixed charge override" do
          result = service.call

          expect(result.fixed_charge.id).to eq(existing_override.id)
          expect(result.fixed_charge.invoice_display_name).to eq("Overridden Fixed Charge")
          expect(result.fixed_charge.units).to eq(10)
        end

        it "calls EmitEventsForActiveSubscriptionsService" do
          allow(FixedCharges::EmitEventsForActiveSubscriptionsService).to receive(:call!)

          service.call

          expect(FixedCharges::EmitEventsForActiveSubscriptionsService).to have_received(:call!).with(
            fixed_charge: existing_override,
            subscription:,
            apply_units_immediately: false
          )
        end

        context "with apply_units_immediately param" do
          let(:params) do
            {
              invoice_display_name: "Overridden Fixed Charge",
              units: "10",
              apply_units_immediately: true
            }
          end

          it "calls EmitEventsForActiveSubscriptionsService with apply_units_immediately true" do
            allow(FixedCharges::EmitEventsForActiveSubscriptionsService).to receive(:call!)

            service.call

            expect(FixedCharges::EmitEventsForActiveSubscriptionsService).to have_received(:call!).with(
              fixed_charge: existing_override,
              subscription:,
              apply_units_immediately: true
            )
          end
        end
      end

      context "when the fixed charge passed is itself an override" do
        let(:overridden_plan) { create(:plan, organization:, parent: plan) }
        let(:subscription) { create(:subscription, customer:, plan: overridden_plan) }
        let(:parent_fixed_charge) { create(:fixed_charge, plan:, organization:, add_on:) }
        let!(:fixed_charge) { create(:fixed_charge, plan: overridden_plan, organization:, add_on:, parent: parent_fixed_charge, code: parent_fixed_charge.code) }

        it "does not create a new fixed charge" do
          expect { service.call }.not_to change(FixedCharge, :count)
        end

        it "updates the existing fixed charge override" do
          result = service.call

          expect(result.fixed_charge.id).to eq(fixed_charge.id)
          expect(result.fixed_charge.invoice_display_name).to eq("Overridden Fixed Charge")
        end
      end

      context "with tax_codes" do
        let(:tax) { create(:tax, organization:) }
        let(:params) do
          {
            invoice_display_name: "Taxed Fixed Charge",
            tax_codes: [tax.code]
          }
        end

        it "applies taxes to the fixed charge override" do
          result = service.call

          expect(result.fixed_charge.taxes).to include(tax)
        end
      end
    end
  end
end
