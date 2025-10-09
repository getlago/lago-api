# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::UpdateService do
  subject(:plans_service) { described_class.new(plan:, params: update_args) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:plan_name) { "Updated plan name" }
  let(:plan_invoice_display_name) { "Updated plan invoice display name" }
  let(:sum_billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:tax1) { create(:tax, organization:) }
  let(:applied_tax) { create(:plan_applied_tax, plan:, tax: tax1) }
  let(:tax2) { create(:tax, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charges_args) do
    [
      {
        add_on_id: add_on.id,
        charge_model: "standard",
        invoice_display_name: "fixed_charge1",
        units: 2,
        properties: {amount: "150"},
        tax_codes: [tax1.code]
      },
      {
        add_on_id: add_on.id,
        charge_model: "graduated",
        invoice_display_name: "fixed_charge2",
        units: 1,
        properties: {
          graduated_ranges: [
            {
              from_value: 0,
              to_value: 10,
              per_unit_amount: "2",
              flat_amount: "0"
            },
            {
              from_value: 11,
              to_value: nil,
              per_unit_amount: "3",
              flat_amount: "3"
            }
          ]
        }
      }
    ]
  end

  let(:update_args) do
    {
      name: plan_name,
      invoice_display_name: plan_invoice_display_name,
      code: "new_plan",
      interval: "monthly",
      pay_in_advance: false,
      amount_cents: 200,
      amount_currency: "EUR",
      tax_codes: [tax2.code],
      charges: charges_args,
      fixed_charges: fixed_charges_args
    }
  end

  let(:minimum_commitment_args) do
    {
      amount_cents: minimum_commitment_amount_cents,
      invoice_display_name: minimum_commitment_invoice_display_name,
      tax_codes: [tax1.code]
    }
  end

  let(:minimum_commitment_invoice_display_name) { "Minimum spending" }
  let(:minimum_commitment_amount_cents) { 100 }

  let(:charges_args) do
    [
      {
        billable_metric_id: sum_billable_metric.id,
        charge_model: "standard",
        invoice_display_name: "charge1",
        min_amount_cents: 100,
        tax_codes: [tax1.code]
      },
      {
        billable_metric_id: billable_metric.id,
        charge_model: "graduated",
        invoice_display_name: "charge2",
        properties: {
          graduated_ranges: [
            {
              from_value: 0,
              to_value: 10,
              per_unit_amount: "2",
              flat_amount: "0"
            },
            {
              from_value: 11,
              to_value: nil,
              per_unit_amount: "3",
              flat_amount: "3"
            }
          ]
        }
      }
    ]
  end

  let(:usage_thresholds_args) do
    [
      {
        id: threshold1.id,
        threshold_display_name: "Threshold 1",
        amount_cents: 1_000
      },
      {
        id: threshold2.id,
        threshold_display_name: "Threshold 2",
        amount_cents: 10_000
      },
      {
        id: threshold3.id,
        threshold_display_name: "Threshold 3",
        amount_cents: 100,
        recurring: true
      }
    ]
  end

  let(:threshold1) do
    create(:usage_threshold, plan:, threshold_display_name: "Threshold 1", amount_cents: 1)
  end

  let(:threshold2) do
    create(:usage_threshold, plan:, threshold_display_name: "Threshold 2", amount_cents: 2)
  end

  let(:threshold3) do
    create(:usage_threshold, :recurring, plan:, threshold_display_name: "Threshold 3", amount_cents: 1)
  end

  let(:threshold5) do
    create(:usage_threshold, plan:, threshold_display_name: "Threshold 5", amount_cents: 123)
  end

  describe "call" do
    before do
      applied_tax
    end

    it "updates a plan" do
      result = plans_service.call

      updated_plan = result.plan

      expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", updated_plan)

      expect(updated_plan.name).to eq("Updated plan name")
      expect(updated_plan.invoice_display_name).to eq(plan_invoice_display_name)
      expect(updated_plan.taxes.pluck(:code)).to eq([tax2.code])
      expect(plan.charges.count).to eq(2)
      expect(plan.charges.order(created_at: :asc).first.invoice_display_name).to eq("charge1")
      expect(plan.charges.order(created_at: :asc).second.invoice_display_name).to eq("charge2")
      expect(plan.fixed_charges.count).to eq(2)
      expect(plan.fixed_charges.order(created_at: :asc).first.invoice_display_name).to eq("fixed_charge1")
      expect(plan.fixed_charges.order(created_at: :asc).second.invoice_display_name).to eq("fixed_charge2")
    end

    it "marks invoices as ready to be refreshed" do
      subscription = create(:subscription, organization:, plan:)
      invoice = create(:invoice, :draft)
      create(:invoice_subscription, invoice:, subscription:)

      expect { plans_service.call }.to change { invoice.reload.ready_to_be_refreshed }.to(true)
    end

    context "with activity logs" do
      context "when no parent" do
        it "produces" do
          described_class.call(plan:, params: update_args)

          expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(plan)
        end
      end

      context "when plan is a children" do
        let(:parent_id) { plan.id }
        let(:child_plan) { create(:plan, organization:, parent_id:) }

        it "does not produce" do
          described_class.call(plan: child_plan, params: update_args)

          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end
    end

    context "with cascade option" do
      let(:child_plan) { create(:plan, organization:, parent_id:) }
      let(:parent_id) { plan.id }

      before do
        child_plan
        update_args[:cascade_updates] = true
      end

      context "when cascade is true and there is no children plans" do
        let(:parent_id) { nil }

        it "does not enqueue the job for updating subscription fee" do
          expect do
            plans_service.call
          end.not_to have_enqueued_job(Plans::UpdateAmountJob)
        end
      end

      context "when cascade is true and child plan is already updated" do
        let(:child_plan) { create(:plan, organization:, parent_id:, amount_cents: 150) }

        it "does not enqueue the job for updating subscription fee" do
          expect do
            plans_service.call
          end.not_to have_enqueued_job(Plans::UpdateAmountJob)
        end
      end

      context "when cascade is true with children plans not touched" do
        it "enqueues the job for updating subscription fee" do
          expect do
            plans_service.call
          end.to have_enqueued_job(Plans::UpdateAmountJob)
        end
      end

      context "when cascade is false with children plans not touched" do
        before do
          update_args[:cascade_updates] = false
        end

        it "does not enqueue the job for updating subscription fee" do
          expect do
            plans_service.call
          end.not_to have_enqueued_job(Plans::UpdateAmountJob)
        end
      end
    end

    context "when thresholds are present" do
      let(:usage_thresholds) do
        updated_plan.usage_thresholds.order(threshold_display_name: :asc)
      end

      let(:updated_plan) { plans_service.call.plan }

      before do
        threshold1
        threshold2
        threshold3
        threshold5
      end

      context "with premium license" do
        around { |test| lago_premium!(&test) }

        context "when progressive billing premium integration is present" do
          before do
            plan.organization.update!(premium_integrations: ["progressive_billing"])
          end

          context "when thresholds args are passed" do
            before do
              update_args[:usage_thresholds] = usage_thresholds_args

              update_args[:usage_thresholds] << {
                threshold_display_name: "Threshold 4",
                amount_cents: 4_000
              }
            end

            it "updates the existing thresholds" do
              aggregate_failures do
                expect(usage_thresholds.first).to have_attributes(amount_cents: 1_000)
                expect(usage_thresholds.second).to have_attributes(amount_cents: 10_000)
                expect(usage_thresholds.third).to have_attributes(amount_cents: 100)
                expect(usage_thresholds.fourth).to have_attributes(amount_cents: 4_000)
              end
            end

            it "creates new thresholds and deletes thresholds that are not in the args" do
              aggregate_failures do
                expect(plan.usage_thresholds.count).to eq(4)
                expect(plan.usage_thresholds.order(threshold_display_name: :asc).last.amount_cents).to eq(123)
                expect(usage_thresholds.count).to eq(4)
                expect(usage_thresholds.fourth).to have_attributes(amount_cents: 4_000)
              end
            end
          end

          context "when thresholds args are passed as empty array" do
            before do
              update_args[:usage_thresholds] = []
            end

            it "deletes all existing thresholds" do
              expect(usage_thresholds.count).to eq(0)
            end
          end

          context "when thresholds args are not passed" do
            it "does not update the thresholds" do
              aggregate_failures do
                expect(usage_thresholds.count).to eq(4)
                expect(usage_thresholds.fourth).to have_attributes(
                  threshold_display_name: "Threshold 5"
                )
              end
            end
          end
        end
      end
    end

    context "when thresholds are not present" do
      let(:usage_thresholds) do
        updated_plan.usage_thresholds.order(threshold_display_name: :asc)
      end

      let(:updated_plan) { plans_service.call.plan }

      context "without premium license" do
        it "does not create progressive billing thresholds" do
          expect(usage_thresholds.count).to eq(0)
        end
      end

      context "with premium license" do
        around { |test| lago_premium!(&test) }

        context "when progressive billing premium integration is not present" do
          it "does not create progressive billing thresholds" do
            expect(usage_thresholds.count).to eq(0)
          end
        end

        context "when progressive billing premium integration is present" do
          before do
            plan.organization.update!(premium_integrations: ["progressive_billing"])
          end

          context "when thresholds args are passed" do
            before do
              update_args[:usage_thresholds] = usage_thresholds_args
            end

            it "creates new thresholds" do
              aggregate_failures do
                expect(usage_thresholds.count).to eq(3)
                expect(usage_thresholds.first).to have_attributes(
                  amount_cents: 1_000
                )
                expect(usage_thresholds.second).to have_attributes(
                  amount_cents: 10_000
                )
                expect(usage_thresholds.third).to have_attributes(
                  amount_cents: 100
                )
              end
            end
          end
        end
      end
    end

    context "when charges are not passed" do
      let(:charge) { create(:standard_charge, plan:) }
      let(:update_args) do
        {
          name: plan_name,
          code: "new_plan",
          interval: "monthly",
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: "EUR"
        }
      end

      before { charge }

      it "does not sanitize charges" do
        result = plans_service.call

        updated_plan = result.plan
        aggregate_failures do
          expect(updated_plan.name).to eq("Updated plan name")
          expect(plan.charges.count).to eq(1)
        end
      end
    end

    context "when plan amount is updated" do
      let(:new_customer) { create(:customer, organization:) }
      let(:subscription) { create(:subscription, plan:, customer: new_customer) }
      let(:update_args) do
        {
          name: plan_name,
          code: "new_plan",
          interval: "monthly",
          pay_in_advance: false,
          amount_cents: 5,
          amount_currency: "EUR"
        }
      end

      before { subscription }

      it "correctly updates plan" do
        result = plans_service.call

        updated_plan = result.plan
        aggregate_failures do
          expect(updated_plan.name).to eq("Updated plan name")
          expect(updated_plan.amount_cents).to eq(5)
        end
      end

      context "when there are pending subscriptions which are not relevant after the amount cents decrease" do
        let(:pending_plan) { create(:plan, organization:, amount_cents: 10) }
        let(:pending_subscription) do
          create(:subscription, plan: pending_plan, status: :pending, previous_subscription_id: subscription.id)
        end

        before { pending_subscription }

        it "correctly cancels pending subscriptions" do
          result = plans_service.call

          updated_plan = result.plan
          aggregate_failures do
            expect(updated_plan.name).to eq("Updated plan name")
            expect(updated_plan.amount_cents).to eq(5)
            expect(Subscription.find_by(id: pending_subscription.id).status).to eq("canceled")
          end
        end
      end

      context "when there are pending subscriptions which are not relevant after the amount cents increase" do
        let(:original_plan) { create(:plan, organization:, amount_cents: 150) }
        let(:subscription) { create(:subscription, plan: original_plan, customer: new_customer) }
        let(:pending_subscription) do
          create(:subscription, plan:, status: :pending, previous_subscription_id: subscription.id)
        end
        let(:update_args) do
          {
            name: plan_name,
            code: "new_plan",
            interval: "monthly",
            pay_in_advance: false,
            amount_cents: 200,
            amount_currency: "EUR"
          }
        end
        let(:plan_upgrade_result) { BaseService::Result.new }

        before do
          allow(Subscriptions::PlanUpgradeService)
            .to receive(:call)
            .and_return(plan_upgrade_result)

          pending_subscription
        end

        it "upgrades subscription plan" do
          plans_service.call

          expect(Subscriptions::PlanUpgradeService).to have_received(:call)
        end

        it "updates the plan", :aggregate_failures do
          result = plans_service.call

          expect(result.plan.name).to eq("Updated plan name")
          expect(result.plan.amount_cents).to eq(200)
        end

        context "when pending subscription does not have a previous one" do
          let(:pending_subscription) do
            create(:subscription, plan:, status: :pending, previous_subscription_id: nil)
          end

          it "does not upgrade it" do
            plans_service.call

            expect(Subscriptions::PlanUpgradeService).not_to have_received(:call)
          end
        end

        context "when subscription upgrade fails" do
          let(:plan_upgrade_result) do
            BaseService::Result.new.validation_failure!(
              errors: {billing_time: ["value_is_invalid"]}
            )
          end

          it "returns an error", :aggregate_failures do
            result = plans_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages).to eq({billing_time: ["value_is_invalid"]})
          end
        end
      end
    end

    context "when plan is not found" do
      let(:applied_tax) { nil }
      let(:plan) { nil }

      it "returns an error" do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq("plan_not_found")
        end
      end
    end

    context "with validation error" do
      let(:plan_name) { nil }

      it "returns an error" do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(["value_is_mandatory"])
        end
      end

      context "with new charge" do
        let(:plan_name) { "foo" }

        let(:charges_args) do
          [
            {
              billable_metric_id: sum_billable_metric.id,
              charge_model: "standard",
              pay_in_advance: false,
              invoiceable: true,
              properties: {
                amount: "100"
              }
            }
          ]
        end

        it "updates the plan" do
          result = plans_service.call
          expect(result.plan.charges.count).to eq(1)
        end
      end

      context "with premium charge model" do
        let(:plan_name) { "foo" }

        let(:charges_args) do
          [
            {
              billable_metric_id: sum_billable_metric.id,
              charge_model: "graduated_percentage",
              pay_in_advance: true,
              invoiceable: false,
              properties: {
                graduated_percentage_ranges: [
                  {
                    from_value: 0,
                    to_value: 10,
                    rate: "3",
                    flat_amount: "0"
                  },
                  {
                    from_value: 11,
                    to_value: nil,
                    rate: "2",
                    flat_amount: "3"
                  }
                ]
              }
            }
          ]
        end

        it "returns an error" do
          result = plans_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:charge_model]).to eq(["graduated_percentage_requires_premium_license"])
          end
        end

        context "when premium" do
          around { |test| lago_premium!(&test) }

          it "saves premium charge model" do
            plans_service.call

            expect(plan.charges.graduated_percentage.first).to have_attributes(
              {
                pay_in_advance: true,
                invoiceable: false,
                charge_model: "graduated_percentage"
              }
            )
          end
        end
      end
    end

    context "with metrics from other organization" do
      let(:billable_metric) { create(:billable_metric) }

      it "returns an error" do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq("billable_metrics_not_found")
        end
      end
    end

    context "when plan has no minimum commitment" do
      context "when minimum commitment arguments are present" do
        before { update_args.merge!({minimum_commitment: minimum_commitment_args}) }

        context "when license is premium" do
          around { |test| lago_premium!(&test) }

          it "creates minimum commitment" do
            result = plans_service.call
            commitment = result.plan.minimum_commitment

            aggregate_failures do
              expect(commitment.amount_cents).to eq(minimum_commitment_args[:amount_cents])
              expect(commitment.invoice_display_name).to eq(minimum_commitment_args[:invoice_display_name])
            end
          end
        end

        context "when license is not premium" do
          it "does not create minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment).to be_nil
          end
        end
      end

      context "when minimum commitment arguments are not present" do
        context "when license is premium" do
          around { |test| lago_premium!(&test) }

          it "does not create minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment).to be_nil
          end
        end

        context "when license is not premium" do
          it "does not create minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment).to be_nil
          end
        end
      end

      context "when minimum commitment arguments is an empty hash" do
        before { update_args.merge!({minimum_commitment: {}}) }

        context "when license is premium" do
          around { |test| lago_premium!(&test) }

          it "does not create minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment).to be_nil
          end
        end

        context "when license is not premium" do
          it "does not create minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment).to be_nil
          end
        end
      end
    end

    context "when plan has minimum commitment" do
      let(:minimum_commitment) { create(:commitment, plan:) }

      before { minimum_commitment }

      context "when minimum commitment arguments are present" do
        before { update_args.merge!({minimum_commitment: minimum_commitment_args}) }

        context "when license is premium" do
          around { |test| lago_premium!(&test) }

          it "updates minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment.amount_cents).to eq(minimum_commitment_args[:amount_cents])
          end
        end

        context "when license is not premium" do
          it "does not update minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment.amount_cents).not_to eq(update_args[:amount_cents])
          end
        end
      end

      context "when only some minimum commitment arguments are present" do
        let(:minimum_commitment_args) do
          {invoice_display_name: minimum_commitment_invoice_display_name}
        end

        before { update_args.merge!({minimum_commitment: minimum_commitment_args}) }

        context "when license is premium" do
          around { |test| lago_premium!(&test) }

          it "does not update minimum commitment args that are not present" do
            result = plans_service.call

            aggregate_failures do
              expect(result.plan.minimum_commitment.invoice_display_name).to eq(minimum_commitment_invoice_display_name)
              expect(result.plan.minimum_commitment.amount_cents).to eq(minimum_commitment.amount_cents)
            end
          end
        end

        context "when license is not premium" do
          it "does not update minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment.invoice_display_name).to eq(minimum_commitment.invoice_display_name)
            expect(result.plan.minimum_commitment.amount_cents).to eq(minimum_commitment.amount_cents)
          end
        end
      end

      context "when minimum commitment arguments are not present" do
        context "when license is premium" do
          around { |test| lago_premium!(&test) }

          it "does not update minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment.amount_cents).not_to eq(update_args[:amount_cents])
          end
        end

        context "when license is not premium" do
          it "does not update minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment.amount_cents).not_to eq(update_args[:amount_cents])
          end
        end
      end

      context "when minimum commitment arguments is an empty hash" do
        before { update_args.merge!({minimum_commitment: {}}) }

        context "when license is premium" do
          around { |test| lago_premium!(&test) }

          it "deletes plan minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment).to be_nil
          end
        end

        context "when license is not premium" do
          it "does not delete minimum commitment" do
            result = plans_service.call

            expect(result.plan.minimum_commitment).not_to be_nil
          end
        end
      end
    end

    context "with existing charges" do
      let!(:existing_charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: sum_billable_metric.id,
          amount_currency: "USD",
          properties: {
            amount: "300"
          }
        )
      end

      let(:billable_metric_filter) do
        create(
          :billable_metric_filter,
          billable_metric: sum_billable_metric,
          key: "payment_method",
          values: %w[card physical]
        )
      end

      let(:update_args) do
        {
          id: plan.id,
          name: plan_name,
          code: "new_plan",
          interval: "monthly",
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: "EUR",
          charges: [
            {
              id: existing_charge.id,
              billable_metric_id: sum_billable_metric.id,
              charge_model: "standard",
              pay_in_advance: true,
              prorated: true,
              invoiceable: false,
              filters: [
                {
                  invoice_display_name: "Card filter",
                  properties: {amount: "90"},
                  values: {billable_metric_filter.key => ["card"]}
                }
              ]
            },
            {
              billable_metric_id: billable_metric.id,
              charge_model: "standard",
              min_amount_cents: 100,
              properties: {
                amount: "300"
              },
              tax_codes: [tax1.code]
            }
          ]
        }
      end

      it "updates existing charge and creates an other one" do
        expect { plans_service.call }.to change(Charge, :count).by(1)

        charge = plan.charges.where(pay_in_advance: false).first
        expect(charge.taxes.pluck(:code)).to eq([tax1.code])
      end

      it "updates existing charge" do
        plans_service.call

        expect(existing_charge.reload).to have_attributes(
          prorated: true,
          properties: {"amount" => "0"}
        )

        expect(existing_charge.filters.first).to have_attributes(
          invoice_display_name: "Card filter",
          properties: {"amount" => "90"}
        )
        expect(existing_charge.filters.first.values.first).to have_attributes(
          billable_metric_filter_id: billable_metric_filter.id,
          values: ["card"]
        )
      end

      it "does not update premium attributes" do
        plan = plans_service.call.plan

        expect(existing_charge.reload).to have_attributes(pay_in_advance: true, invoiceable: true)
        expect(plan.charges.where(pay_in_advance: false).first.min_amount_cents).to eq(0)
      end

      context "when premium" do
        around { |test| lago_premium!(&test) }

        it "saves premium attributes" do
          plans_service.call

          expect(existing_charge.reload).to have_attributes(pay_in_advance: true, invoiceable: false)
          charge = plan.charges.where(pay_in_advance: false).first
          expect(charge.min_amount_cents).to eq(100)
        end
      end

      context "with cascade option and update charge case" do
        let(:child_plan) { create(:plan, organization:, parent_id:) }
        let(:parent_id) { plan.id }
        let(:charge_parent_id) { existing_charge.id }
        let(:child_charge) do
          create(
            :standard_charge,
            plan_id: child_plan.id,
            parent_id: charge_parent_id,
            billable_metric_id: sum_billable_metric.id,
            properties: {amount: "300"}
          )
        end

        before do
          child_charge
          update_args[:cascade_updates] = true
        end

        context "when cascade is true and there is no children plans" do
          let(:parent_id) { nil }

          it "does not enqueue the job for updating charge" do
            expect do
              plans_service.call
            end.not_to have_enqueued_job(Charges::UpdateChildrenJob)
          end
        end

        context "when cascade is true and there are children plans" do
          it "enqueues the job for updating charge" do
            expect do
              plans_service.call
            end.to have_enqueued_job(Charges::UpdateChildrenJob)
          end
        end

        context "when cascade is false with children plans" do
          before do
            update_args[:cascade_updates] = false
          end

          it "does not enqueue the job for updating charge" do
            expect do
              plans_service.call
            end.not_to have_enqueued_job(Charges::DestroyChildrenJob)
          end
        end
      end

      context "with cascade option and create charge case" do
        let(:child_plan) { create(:plan, organization:, parent_id:) }
        let(:parent_id) { plan.id }

        before do
          child_plan
          update_args[:cascade_updates] = true
        end

        context "when cascade is true and there is no children plans" do
          let(:parent_id) { nil }

          it "does not enqueue the job for creating new charge" do
            expect do
              plans_service.call
            end.not_to have_enqueued_job(Charges::CreateChildrenJob)
          end
        end

        context "when cascade is true and there are children plans" do
          it "enqueues the job for creating new charge" do
            expect do
              plans_service.call
            end.to have_enqueued_job(Charges::CreateChildrenJob)
              .with(charge: Charge, payload: Hash)
          end
        end

        context "when cascade is false with children plans" do
          before do
            update_args[:cascade_updates] = false
          end

          it "does not enqueue the job for creating new charge" do
            expect do
              plans_service.call
            end.not_to have_enqueued_job(Charges::CreateChildrenJob)
          end
        end
      end
    end

    context "with existing charge attached to subscription" do
      let(:existing_charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: sum_billable_metric.id,
          amount_currency: "USD",
          properties: {
            amount: "300"
          }
        )
      end

      let(:subscription) { create(:subscription, plan:) }

      let(:update_args) do
        {
          id: plan.id,
          code: "new_plan",
          amount_cents: 200,
          charges: [
            {
              id: existing_charge.id,
              billable_metric_id: sum_billable_metric.id,
              charge_model: "standard",
              tax_codes: [tax2.code]
            }
          ]
        }
      end

      before do
        existing_charge && subscription
      end

      it "updates existing charge", :aggregate_failures do
        expect { plans_service.call }.not_to change(Charge, :count)
        expect(plan.charges.first.taxes.pluck(:code)).to eq([tax2.code])
      end
    end

    context "with charge to delete" do
      let(:subscription) { create(:subscription, plan:) }
      let(:charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: billable_metric.id,
          properties: {amount: "300"}
        )
      end

      let(:update_args) do
        {
          id: plan.id,
          name: plan_name,
          code: "new_plan",
          interval: "monthly",
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: "EUR",
          charges: []
        }
      end

      let(:billable_metric) { sum_billable_metric }

      before do
        subscription
        charge
      end

      it "discards the charge" do
        freeze_time do
          expect { plans_service.call }
            .to change { charge.reload.deleted_at }.from(nil).to(Time.current)
        end
      end

      context "with cascade option" do
        let(:child_plan) { create(:plan, organization:, parent_id:) }
        let(:parent_id) { plan.id }
        let(:charge_parent_id) { charge.id }
        let(:child_charge) do
          create(
            :standard_charge,
            plan_id: child_plan.id,
            parent_id: charge_parent_id,
            billable_metric_id: billable_metric.id,
            properties: {amount: "300"}
          )
        end

        before do
          child_charge
          update_args[:cascade_updates] = true
        end

        context "when cascade is true and there is no children plans" do
          let(:parent_id) { nil }

          it "does not enqueue the job for removing charge" do
            expect do
              plans_service.call
            end.not_to have_enqueued_job(Charges::DestroyChildrenJob)
          end
        end

        context "when cascade is true and there are children plans" do
          it "enqueues the job for removing charge" do
            expect do
              plans_service.call
            end.to have_enqueued_job(Charges::DestroyChildrenJob)
          end
        end

        context "when cascade is false with children plans" do
          before do
            update_args[:cascade_updates] = false
          end

          it "does not enqueue the job for removing charge" do
            expect do
              plans_service.call
            end.not_to have_enqueued_job(Charges::DestroyChildrenJob)
          end
        end
      end
    end

    context "when attached to a subscription" do
      let(:existing_charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: sum_billable_metric.id,
          properties: {
            amount: "300"
          }
        )
      end

      let(:update_args) do
        {
          id: plan.id,
          name: plan_name,
          code: "new_plan",
          interval: "monthly",
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: "EUR",
          charges: [
            {
              id: existing_charge.id,
              billable_metric_id: sum_billable_metric.id,
              charge_model: "standard",
              properties: {
                amount: "100"
              }
            },
            {
              billable_metric_id: billable_metric.id,
              charge_model: "standard",
              properties: {
                amount: "300"
              }
            }
          ]
        }
      end

      before do
        create(:subscription, plan:)
      end

      it "updates only name description and new charges" do
        result = plans_service.call
        updated_plan = result.plan

        expect(updated_plan.name).to eq("Updated plan name")
        expect(plan.charges.count).to eq(2)
      end
    end

    context "with bill_charges_monthly functionality" do
      context "when interval is yearly and bill_fixed_charges_monthly is sent" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "yearly",
            bill_charges_monthly: true
          }
        end

        it "updates bill_charges_monthly" do
          result = plans_service.call

          expect(result.plan.bill_charges_monthly).to eq(true)
        end
      end

      context "when interval is yearly and bill_charges_monthly is not provided" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "yearly"
          }
        end

        it "sets bill_charges_monthly to false" do
          result = plans_service.call

          expect(result.plan.bill_charges_monthly).to eq(false)
        end
      end

      context "when interval is semiannual and bill_charges_monthly is sent" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "semiannual",
            bill_charges_monthly: true
          }
        end

        it "updates bill_charges_monthly" do
          result = plans_service.call

          expect(result.plan.bill_charges_monthly).to eq(true)
        end
      end

      context "when interval is semiannual and bill_charges_monthly is not provided" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "semiannual"
          }
        end

        it "sets bill_charges_monthly to false" do
          result = plans_service.call

          expect(result.plan.bill_charges_monthly).to eq(false)
        end
      end

      context "when interval is not yearly or semiannual" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "monthly",
            bill_charges_monthly: true
          }
        end

        it "does not set bill_charges_monthly" do
          result = plans_service.call

          expect(result.plan.bill_charges_monthly).to be_nil
        end
      end
    end

    context "with bill_fixed_charges_monthly functionality" do
      context "when interval is yearly and bill_fixed_charges_monthly is sent" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "yearly",
            bill_fixed_charges_monthly: true
          }
        end

        it "updates bill_fixed_charges_monthly" do
          result = plans_service.call

          expect(result.plan.bill_fixed_charges_monthly).to eq(true)
        end
      end

      context "when interval is yearly and bill_fixed_charges_monthly is not provided" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "yearly"
          }
        end

        it "sets bill_fixed_charges_monthly to false" do
          result = plans_service.call

          expect(result.plan.bill_fixed_charges_monthly).to eq(false)
        end
      end

      context "when interval is semiannual and bill_fixed_charges_monthly is sent" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "semiannual",
            bill_fixed_charges_monthly: true
          }
        end

        it "updates bill_fixed_charges_monthly" do
          result = plans_service.call

          expect(result.plan.bill_fixed_charges_monthly).to eq(true)
        end
      end

      context "when interval is semiannual and bill_fixed_charges_monthly is not provided" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "semiannual"
          }
        end

        it "sets bill_fixed_charges_monthly to false" do
          result = plans_service.call

          expect(result.plan.bill_fixed_charges_monthly).to eq(false)
        end
      end

      context "when interval is not yearly or semiannual" do
        let(:update_args) do
          {
            name: plan_name,
            interval: "monthly",
            bill_fixed_charges_monthly: true
          }
        end

        it "does not set bill_fixed_charges_monthly" do
          result = plans_service.call

          expect(result.plan.bill_fixed_charges_monthly).to be_nil
        end
      end
    end

    context "with fixed_charges validation" do
      context "when fixed_charges are valid" do
        let(:update_args) do
          {
            name: plan_name,
            fixed_charges: fixed_charges_args
          }
        end

        it "validates fixed_charges successfully" do
          result = plans_service.call

          expect(result).to be_success
        end
      end

      context "when fixed_charges add_on is not found" do
        let(:update_args) do
          {
            name: plan_name,
            fixed_charges: [
              {
                add_on_id: add_on.code,
                charge_model: "standard",
                units: 1,
                properties: {amount: "100"}
              }
            ]
          }
        end

        it "returns validation error" do
          result = plans_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("add_ons_not_found")
        end
      end

      context "when no fixed_charges are provided" do
        let(:update_args) do
          {
            name: plan_name
          }
        end

        it "does not validate fixed_charges" do
          result = plans_service.call

          expect(result).to be_success
        end
      end

      context "when both charges and fixed_charges are provided" do
        let(:update_args) do
          {
            name: plan_name,
            charges: charges_args,
            fixed_charges: fixed_charges_args
          }
        end

        it "validates both successfully" do
          result = plans_service.call

          expect(result).to be_success
        end
      end
    end

    context "with fixed_charges flow" do
      let(:update_args) do
        {
          name: plan_name,
          interval: "yearly",
          bill_fixed_charges_monthly: true,
          fixed_charges: fixed_charges_args
        }
      end

      context "when plan has no fixed_charges" do
        it "handles adding fixed_charges flow successfully" do
          result = plans_service.call

          expect(result).to be_success
          expect(result.plan.bill_fixed_charges_monthly).to eq(true)
          expect(result.plan.fixed_charges.count).to eq(2)
          expect(result.plan.fixed_charges.map(&:invoice_display_name)).to match_array(["fixed_charge1", "fixed_charge2"])
        end
      end

      context "when plan has fixed_charges" do
        let(:fixed_charge_to_update) { create(:fixed_charge, plan:, invoice_display_name: "fixed_charge_to_update", units: 1, add_on:) }
        let(:fixed_charge_to_delete) { create(:fixed_charge, plan:, invoice_display_name: "fixed_charge_to_delete", units: 2) }
        let(:fixed_charges_args) do
          [
            {
              id: fixed_charge_to_update.id,
              add_on_id: add_on.id,
              charge_model: "standard",
              invoice_display_name: "fixed_charge1",
              units: 2,
              properties: {amount: "150"},
              tax_codes: [tax1.code]
            },
            {
              add_on_id: add_on.id,
              charge_model: "graduated",
              invoice_display_name: "fixed_charge2",
              units: 1,
              properties: {
                graduated_ranges: [
                  {
                    from_value: 0,
                    to_value: 10,
                    per_unit_amount: "2",
                    flat_amount: "0"
                  },
                  {
                    from_value: 11,
                    to_value: nil,
                    per_unit_amount: "3",
                    flat_amount: "3"
                  }
                ]
              }
            }
          ]
        end

        before do
          fixed_charge_to_update
          fixed_charge_to_delete
          update_args[:cascade_updates] = true
        end

        it "handles update, edit and delete fixed_charges flow successfully" do
          result = plans_service.call

          expect(result).to be_success
          expect(result.plan.fixed_charges.count).to eq(2)
          expect(result.plan.fixed_charges.map(&:id)).to include(fixed_charge_to_update.id)
          expect(result.plan.fixed_charges.map(&:id)).not_to include(fixed_charge_to_delete.id)
        end

        context "when plan has children" do
          let(:parent_id) { plan.id }
          let(:child_plan) { create(:plan, organization:, parent_id:) }

          before { child_plan }

          it "schedules job to update fixed_charges of children plans" do
            expect do
              plans_service.call
            end.to have_enqueued_job(FixedCharges::UpdateChildrenJob).exactly(1).times
          end

          it "schedules job to create fixed_charges of children plans" do
            expect do
              plans_service.call
            end.to have_enqueued_job(FixedCharges::CreateChildrenJob).exactly(1).times
          end

          it "schedules job to delete fixed_charges of children plans" do
            expect do
              plans_service.call
            end.to have_enqueued_job(FixedCharges::DestroyChildrenJob).exactly(1).times
          end
        end
      end
    end
  end
end
