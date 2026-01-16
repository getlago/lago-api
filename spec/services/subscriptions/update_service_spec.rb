# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::UpdateService do
  subject(:update_service) { described_class.new(subscription:, params:) }

  let(:membership) { create(:membership) }
  let(:subscription) { create(:subscription) }

  describe "#call" do
    let(:subscription_at) { "2022-07-07T00:00:00Z" }
    let(:ending_at) { Time.current.beginning_of_day + 1.month }

    let(:params) do
      {
        name: "new name",
        ending_at:,
        subscription_at:
      }
    end

    before do
      subscription
    end

    context "when subscription is already active" do
      it "updates the subscription and ignores subscription_at" do
        result = update_service.call

        expect(result).to be_a(BaseResult)
        expect(result).to be_success

        expect(result.subscription.name).to eq("new name")
        expect(result.subscription.ending_at).to eq(Time.current.beginning_of_day + 1.month)
        expect(result.subscription.subscription_at.to_s).not_to include("2022-07-07")
      end

      it "sends updated subscription webhook" do
        expect { update_service.call }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
      end

      it "does not sync to Hubspot" do
        expect { update_service.call }.not_to have_enqueued_job(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob)
      end

      it "produces an activity log after commit" do
        described_class.call(subscription:, params:)

        expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
      end

      context "when subscription should be synced with Hubspot" do
        let(:params) { {name: "new name"} }
        let(:customer) { create(:customer, :with_hubspot_integration) }
        let(:subscription) { create(:subscription, customer:) }

        it "enqueues a job to update Hubspot subscription" do
          expect {
            result = update_service.call

            expect(result).to be_success
          }.to have_enqueued_job_after_commit(Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob).with(subscription:)
        end
      end

      context "when subscription_at is not passed at all" do
        let(:params) { {name: "new name"} }

        it "updates the subscription" do
          result = update_service.call

          expect(result).to be_success

          expect(result.subscription.name).to eq("new name")
          expect(result.subscription.subscription_at.to_s).not_to include("2022-07-07")
        end
      end

      context "when updating on_termination_credit_note" do
        let(:params) { {on_termination_credit_note: "credit"} }

        context "with pay_in_advance plan" do
          let(:plan) { create(:plan, :pay_in_advance) }
          let(:subscription) { create(:subscription, plan:) }

          %w[credit skip].each do |value|
            context "when on_termination_credit_note is #{value}" do
              let(:params) { {on_termination_credit_note: value} }

              it "accepts the value for pay_in_advance plans" do
                result = update_service.call

                expect(result).to be_success
                expect(result.subscription.on_termination_credit_note).to eq(value)
              end
            end
          end
        end

        context "with pay_in_arrears plan" do
          it "ignores the value" do
            result = update_service.call

            expect(result).to be_success
            expect(result.subscription.on_termination_credit_note).to be_nil
          end
        end
      end

      context "when updating on_termination_invoice" do
        let(:params) { {on_termination_invoice: "generate"} }

        %w[generate skip].each do |value|
          context "when on_termination_invoice is #{value}" do
            let(:params) { {on_termination_invoice: value} }

            it "accepts the value" do
              result = update_service.call

              expect(result).to be_success
              expect(result.subscription.on_termination_invoice).to eq(value)
            end
          end
        end
      end

      context "when updating payment method" do
        let(:payment_method) { create(:payment_method, organization: subscription.organization, customer: subscription.customer) }
        let(:params) { {payment_method: payment_method_params} }
        let(:payment_method_params) do
          {
            payment_method_id: payment_method.id,
            payment_method_type: "provider"
          }
        end

        before { payment_method }

        it "updates the subscription" do
          result = update_service.call

          expect(result).to be_success
          expect(result.subscription.reload.payment_method_id).to eq(payment_method_params[:payment_method_id])
          expect(result.subscription.reload.payment_method_type).to eq("provider")
        end

        context "when payment method is already attached" do
          before do
            subscription.payment_method = payment_method
            subscription.payment_method_type = "provider"
          end

          let(:payment_method_params) do
            {
              payment_method_id: nil,
              payment_method_type: "provider"
            }
          end

          it "removes payment_method" do
            result = update_service.call

            expect(result).to be_success
            expect(result.subscription.reload.payment_method_id).to eq(nil)
            expect(result.subscription.reload.payment_method_type).to eq("provider")
          end
        end
      end

      context "when plan has fixed charges" do
        let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan) }

        before { fixed_charge }

        it "does not create fixed charge events" do
          expect { update_service.call }.not_to change(FixedChargeEvent, :count)
        end
      end
    end

    context "when subscription is starting in the future" do
      let(:subscription) { create(:subscription, :pending) }

      it "does not produce activity log" do
        update_service.call

        expect(Utils::ActivityLog).not_to have_received(:produce)
      end

      context "when subscription is pay_in_advance" do
        let(:plan) { create(:plan, :pay_in_advance) }
        let(:subscription) { create(:subscription, :pending, plan:) }

        context "when subscription_at is set to past date" do
          it "updates the subscription_at as well" do
            result = update_service.call

            expect(result).to be_success

            expect(result.subscription.name).to eq("new name")
            expect(result.subscription.subscription_at.to_s).to eq("2022-07-07 00:00:00 UTC")
          end

          it "does not enqueue a job to bill the subscription" do
            expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end

          context "when plan has pay in advance fixed charges" do
            let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan, pay_in_advance: true) }

            before { fixed_charge }

            it "creates fixed charge events" do
              expect { update_service.call }.to change(FixedChargeEvent, :count).by(1)
              expect(subscription.fixed_charge_events.pluck(:fixed_charge_id, :timestamp))
                .to contain_exactly([fixed_charge.id, be_within(1.second).of(subscription.started_at)])
            end

            it "does not enqueue a job to bill the pay in advance fixed charges" do
              expect { update_service.call }.not_to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
            end
          end
        end

        context "when subscription date is set to today" do
          around do |test|
            travel_to("2022-07-07T01:00:00Z") do
              test.run
            end
          end

          it "activates subscription" do
            result = update_service.call

            expect(result).to be_success

            expect(result.subscription.name).to eq("new name")
            expect(result.subscription.status).to eq("active")
            expect(result.subscription.subscription_at.to_s).to eq subscription.subscription_at.to_s
          end

          it "enqueues a job to bill the subscription" do
            expect { update_service.call }.to have_enqueued_job_after_commit(BillSubscriptionJob)
              .with([subscription], Time.now.to_i, invoicing_reason: :subscription_starting)
          end

          context "when plan has fixed charges" do
            let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan) }

            before { fixed_charge }

            it "creates fixed charge events" do
              expect { update_service.call }.to change(FixedChargeEvent, :count).by(1)
              expect(subscription.fixed_charge_events.pluck(:fixed_charge_id, :timestamp))
                .to contain_exactly([fixed_charge.id, be_within(1.second).of(subscription.started_at)])
            end
          end
        end

        context "when subscription_at is set to future date" do
          let(:subscription_at) { 1.week.from_now.iso8601 }

          it "keeps subscription pending and updates subscription_at" do
            result = update_service.call

            expect(result).to be_success
            expect(result.subscription.status).to eq("pending")
            expect(result.subscription.subscription_at).to eq(subscription_at)
          end

          it "does not enqueue billing job" do
            expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end

          context "when plan has fixed charges" do
            let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan) }

            before { fixed_charge }

            it "does not create fixed charge events" do
              expect { update_service.call }.not_to change(FixedChargeEvent, :count)
            end
          end
        end
      end

      context "when plan is NOT pay_in_advance" do
        context "when subscription_at is today" do
          let(:subscription_at) { Time.current }

          it "does not enqueue billing job" do
            expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end

          context "when plan has fixed charges" do
            let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan) }

            before { fixed_charge }

            it "creates fixed charge events" do
              expect { update_service.call }.to change(FixedChargeEvent, :count).by(1)
              expect(subscription.fixed_charge_events.pluck(:fixed_charge_id, :timestamp))
                .to match_array([[fixed_charge.id, be_within(5.seconds).of(Time.current)]])
            end

            it "does not schedule a BillSubscriptionJob" do
              expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
            end

            context "when at least one fixed_charge is pay in advance" do
              let(:fixed_charge_2) { create(:fixed_charge, plan: subscription.plan, pay_in_advance: true) }

              before { fixed_charge_2 }

              it "does not schedule a BillSubscriptionJob" do
                expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
              end

              it "schedules a Invoices::CreatePayInAdvanceFixedChargesJob" do
                expect { update_service.call }.to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
              end
            end
          end
        end

        context "when subscription_at is in the past" do
          it "does not enqueue a job to bill the subscription" do
            expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
          end

          context "when plan has pay in advance fixed charges" do
            let(:fixed_charge) { create(:fixed_charge, plan: subscription.plan, pay_in_advance: true) }

            before { fixed_charge }

            it "does not enqueue a job to bill the pay in advance fixed charges" do
              expect { update_service.call }.not_to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
            end
          end
        end
      end

      context "when updating subscription without changing subscription_at" do
        let(:params) { {name: "new name"} }

        it "updates the subscription without processing subscription_at change" do
          result = update_service.call

          expect(result).to be_success
          expect(result.subscription.name).to eq("new name")
        end
      end
    end

    context "when subscription is nil" do
      let(:params) do
        {
          name: "new name"
        }
      end

      let(:subscription) { nil }

      it "returns an error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("subscription_not_found")
      end
    end

    context "when validation fails" do
      context "with invalid subscription_at format" do
        let(:params) { {subscription_at: "invalid-date"} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({subscription_at: ["invalid_date"]})
        end
      end

      context "with invalid ending_at format" do
        let(:params) { {ending_at: "invalid-date"} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({ending_at: ["invalid_date"]})
        end
      end

      context "with ending_at in the past" do
        let(:params) { {ending_at: 1.day.ago} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({ending_at: ["invalid_date"]})
        end
      end

      context "with ending_at before subscription_at" do
        let(:params) { {ending_at: 1.day.from_now, subscription_at: 2.days.from_now} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({ending_at: ["invalid_date"]})
        end
      end

      context "when payment method type is not correct" do
        let(:payment_method) { create(:payment_method, organization: subscription.organization, customer: subscription.customer) }
        let(:params) { {payment_method: payment_method_params} }
        let(:payment_method_params) do
          {
            payment_method_id: payment_method.id,
            payment_method_type: "invalid"
          }
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
        end
      end

      context "when payment method id is not correct" do
        let(:payment_method) { create(:payment_method, organization: subscription.organization, customer: subscription.customer) }
        let(:params) { {payment_method: payment_method_params} }
        let(:payment_method_params) do
          {
            payment_method_id: "123",
            payment_method_type: "provider"
          }
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:payment_method]).to eq(["invalid_payment_method"])
        end
      end

      context "with invalid on_termination_credit_note" do
        let(:params) { {on_termination_credit_note: "invalid_value"} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({on_termination_credit_note: ["invalid_value"]})
        end
      end

      context "with invalid on_termination_invoice" do
        let(:params) { {on_termination_invoice: "invalid_value"} }

        it "returns validation failure" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq({on_termination_invoice: ["invalid_value"]})
        end
      end
    end

    context "when plan_overrides" do
      let(:plan) { create(:plan, organization: membership.organization) }
      let(:subscription) { create(:subscription, plan:) }
      let(:params) do
        {
          plan_overrides: {
            name: "new name"
          }
        }
      end

      context "when License is premium" do
        around { |test| lago_premium!(&test) }

        it "creates the new plan accordingly" do
          update_service.call

          expect(subscription.plan.name).to eq("new name")
          expect(subscription.plan_id).not_to eq(plan.id)
          expect(subscription.plan.parent_id).to eq(plan.id)
        end

        context "when plan_overrides params are invalid" do
          let(:params) do
            {
              name: "NEW NAME",
              plan_overrides: {
                amount_currency: "MAGIC-COIN"
              }
            }
          end

          it "returns an error" do
            result = update_service.call

            expect(subscription.reload.name).not_to eq "NEW NAME"
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:amount_currency]).to eq(["value_is_invalid"])
          end
        end

        context "with overriden plan" do
          let(:parent_plan) { create(:plan, organization: membership.organization) }
          let(:plan) { create(:plan, organization: membership.organization, parent_id: parent_plan.id) }

          it "updates the plan accordingly" do
            update_service.call

            expect(subscription.plan.name).to eq("new name")
            expect(subscription.plan_id).to eq(plan.id)
          end

          context "when Plans::UpdateService fails" do
            let(:failed_result) { BaseResult.new.validation_failure!(errors: {name: ["invalid_name"]}) }

            before do
              allow(Plans::UpdateService).to receive(:call!).and_raise(
                BaseService::FailedResult.new(failed_result, "Failed to update plan")
              )
            end

            it "returns the error from Plans::UpdateService" do
              result = update_service.call

              expect(result).to be_failure
              expect(result.error.result.error.messages).to eq({name: ["invalid_name"]})
            end
          end

          context "when Plans::OverrideService fails" do
            let(:plan) { create(:plan, organization: membership.organization) }
            let(:failed_result) { BaseResult.new.validation_failure!(errors: {amount_cents: ["invalid_amount"]}) }

            before do
              allow(Plans::OverrideService).to receive(:call!).and_raise(
                BaseService::FailedResult.new(failed_result, "Failed to override plan")
              )
            end

            it "returns the error from Plans::OverrideService" do
              result = update_service.call

              expect(result).to be_failure
              expect(result.error.result.error.messages).to eq({amount_cents: ["invalid_amount"]})
            end
          end
        end
      end

      context "when License is not premium" do
        let(:params) do
          {
            name: "new name",
            plan_overrides: {
              amount_cents: 0
            }
          }
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("feature_unavailable")
        end
      end

      context "with fixed charge overrides and apply_units_immediately true" do
        around { |test| lago_premium!(&test) }

        let(:organization) { membership.organization }
        let(:plan) { create(:plan, organization:, interval: :weekly) }
        let(:fixed_charge1) { create(:fixed_charge, plan:, units: 5) }
        let(:fixed_charge2) { create(:fixed_charge, plan:, units: 10) }
        let(:customer) { create(:customer, organization:) }
        let(:subscription) do
          create(
            :subscription,
            :calendar,
            plan:,
            customer:,
            subscription_at:,
            started_at:
          )
        end
        let(:subscription_at) { Date.new(2023, 9, 2) }
        let(:started_at) { Date.new(2025, 5, 17) }

        let(:params) do
          {
            plan_overrides: {
              fixed_charges: [
                {
                  id: fixed_charge2.id,
                  units: 300,
                  apply_units_immediately: true
                }
              ]
            }
          }
        end

        before do
          fixed_charge1
          fixed_charge2
          subscription
        end

        it "creates override fixed charges for both fixed charges" do
          expect { update_service.call }.to change(FixedCharge, :count).by(2)

          fc1_override = FixedCharge.find_sole_by(parent_id: fixed_charge1.id)
          fc2_override = FixedCharge.find_sole_by(parent_id: fixed_charge2.id)

          expect(fc1_override.units).to eq(fixed_charge1.units)
          expect(fc2_override.units).to eq(300)
        end

        it "creates 2 fixed charge events with correct timestamps and units" do
          travel_to(Time.zone.local(2025, 10, 10, 15, 33)) do # Friday
            expect { update_service.call }.to change(FixedChargeEvent, :count).by(2)

            fc1_override = FixedCharge.find_sole_by(parent_id: fixed_charge1.id)
            fc2_override = FixedCharge.find_sole_by(parent_id: fixed_charge2.id)

            next_billing_period_start = Time.zone.local(2025, 10, 13) # Next Monday
            events = subscription.fixed_charge_events.pluck(%i[fixed_charge_id units timestamp])

            expect(events).to contain_exactly(
              [fc1_override.id, fixed_charge1.units, be_within(1.second).of(next_billing_period_start)],
              [fc2_override.id, 300, be_within(1.second).of(Time.current)]
            )
          end
        end

        it "does not enqueue billing job" do
          expect { update_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
        end

        it "does not schedule a Invoices::CreatePayInAdvanceFixedChargesJob" do
          expect { update_service.call }.not_to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
        end

        context "when at least one fixed_charge is pay in advance" do
          let(:fixed_charge2) { create(:fixed_charge, plan:, pay_in_advance: true) }

          before { fixed_charge2 }

          it "schedules a Invoices::CreatePayInAdvanceFixedChargesJob" do
            expect { update_service.call }.to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
          end
        end
      end

      context "with fixed charge overrides and apply_units_immediately false" do
        around { |test| lago_premium!(&test) }

        let(:organization) { membership.organization }
        let(:plan) { create(:plan, organization:, interval: :weekly) }
        let(:fixed_charge1) { create(:fixed_charge, plan:, units: 5) }
        let(:fixed_charge2) { create(:fixed_charge, plan:, units: 10) }
        let(:customer) { create(:customer, organization:) }
        let(:subscription) do
          create(
            :subscription,
            :calendar,
            plan:,
            customer:,
            subscription_at:,
            started_at:
          )
        end
        let(:subscription_at) { Date.new(2023, 9, 2) }
        let(:started_at) { Date.new(2025, 5, 17) }

        let(:params) do
          {
            plan_overrides: {
              fixed_charges: [
                {
                  id: fixed_charge1.id,
                  units: 15,
                  apply_units_immediately: false
                },
                {
                  id: fixed_charge2.id
                }
              ]
            }
          }
        end

        before do
          fixed_charge1
          fixed_charge2
          subscription
        end

        it "creates override fixed charges for both fixed charges" do
          expect { update_service.call }.to change(FixedCharge, :count).by(2)

          fc1_override = FixedCharge.find_sole_by(parent_id: fixed_charge1.id)
          fc2_override = FixedCharge.find_sole_by(parent_id: fixed_charge2.id)

          expect(fc1_override.units).to eq(15)
          expect(fc2_override.units).to eq(fixed_charge2.units)
        end

        it "creates 2 fixed charge events with correct timestamps and units" do
          travel_to(Time.zone.local(2025, 10, 10, 15, 33)) do # Friday
            expect { update_service.call }.to change(FixedChargeEvent, :count).by(2)

            fc1_override = FixedCharge.find_sole_by(parent_id: fixed_charge1.id)
            fc2_override = FixedCharge.find_sole_by(parent_id: fixed_charge2.id)

            next_billing_period_start = Time.zone.local(2025, 10, 13) # Next Monday
            events = subscription.fixed_charge_events.pluck(%i[fixed_charge_id units timestamp])

            expect(events).to contain_exactly(
              [fc1_override.id, 15, be_within(1.second).of(next_billing_period_start)],
              [fc2_override.id, fixed_charge2.units, be_within(1.second).of(next_billing_period_start)]
            )
          end
        end

        it "does not schedule a Invoices::CreatePayInAdvanceFixedChargesJob" do
          expect { update_service.call }.not_to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
        end

        context "when at least one fixed_charge is pay in advance" do
          let(:fixed_charge2) { create(:fixed_charge, plan:, pay_in_advance: true) }

          before { fixed_charge2 }

          it "schedules a Invoices::CreatePayInAdvanceFixedChargesJob" do
            expect { update_service.call }.to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
          end
        end
      end

      context "with pending subscription, fixed charge overrides and mixed apply_units_immediately" do
        around { |test| lago_premium!(&test) }

        let(:organization) { membership.organization }
        let(:plan) { create(:plan, organization:, interval: :weekly) }
        let(:fixed_charge1) { create(:fixed_charge, plan:, units: 5) }
        let(:fixed_charge2) { create(:fixed_charge, plan:, units: 10) }
        let(:customer) { create(:customer, organization:) }
        let(:subscription_at) { 7.days.from_now }

        let(:subscription) do
          create(
            :subscription,
            :calendar,
            plan:,
            customer:,
            subscription_at:,
            status: :pending
          )
        end

        let(:params) do
          {
            plan_overrides: {
              fixed_charges: [
                {
                  id: fixed_charge1.id,
                  units: 200,
                  apply_units_immediately: true
                },
                {
                  id: fixed_charge2.id,
                  units: 300,
                  apply_units_immediately: false
                }
              ]
            }
          }
        end

        before do
          fixed_charge1
          fixed_charge2
          subscription
        end

        it "creates override fixed charges for both fixed charges" do
          expect { update_service.call }.to change(FixedCharge, :count).by(2)

          fc1_override = FixedCharge.find_sole_by(parent_id: fixed_charge1.id)
          fc2_override = FixedCharge.find_sole_by(parent_id: fixed_charge2.id)

          expect(fc1_override.units).to eq(200)
          expect(fc2_override.units).to eq(300)
        end

        it "does not create fixed charge events for pending subscription" do
          travel_to(Time.zone.local(2025, 10, 29, 15, 33)) do
            expect { update_service.call }.not_to change(FixedChargeEvent, :count)

            subscription.reload

            expect(subscription).to be_pending
            expect(subscription.plan.parent_id).to eq(plan.id)
            expect(subscription.fixed_charge_events.count).to be_zero
          end
        end
      end
    end

    context "with empty params" do
      let(:params) { {} }

      it "succeeds without making changes" do
        original_name = subscription.name
        result = update_service.call

        expect(result).to be_success
        expect(result.subscription.name).to eq(original_name)
      end
    end

    context "with nil values in params" do
      let(:params) { {name: nil, ending_at: nil} }

      it "handles nil values gracefully" do
        result = update_service.call

        expect(result).to be_success
        expect(result.subscription.name).to be_nil
        expect(result.subscription.ending_at).to be_nil
      end
    end

    context "when customer is missing" do
      let(:subscription) { build(:subscription, customer: nil) }
      let(:params) { {name: "new name"} }

      it "returns customer not found error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end

    context "when plan is missing" do
      let(:subscription) { build(:subscription, plan: nil) }
      let(:params) { {name: "new name"} }

      it "returns plan not found error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end
  end
end
