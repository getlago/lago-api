# frozen_string_literal: true

require "rails_helper"

# Orders::ExecuteService only dispatches here on a premium license, and plan overrides are
# premium-gated downstream.
RSpec.describe Orders::SubscriptionAmendment::ExecuteService, :premium do
  subject(:execute_service) { described_class.new(order:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:, currency: "EUR") }

  let(:target_plan) { create(:plan, organization:, amount_currency: "EUR", amount_cents: 50_000) }
  let(:target_subscription) do
    create(
      :subscription,
      customer:,
      organization:,
      plan: target_plan,
      name: "Original deal",
      external_id: "sub_ext_42",
      billing_time: :anniversary,
      subscription_at: 7.months.ago,
      started_at: 7.months.ago,
      ending_at: 5.months.from_now
    )
  end

  let(:plan) { create(:plan, organization:, amount_currency: "EUR", amount_cents: 100_000) }
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {"amount" => "50"}) }

  let(:plan_item) do
    {
      "id" => plan.id,
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "type" => "plan",
      "payload" => plan_payload,
      "overrides" => plan_overrides
    }.compact
  end
  let(:plan_payload) do
    {
      "code" => plan.code,
      "subscriptionName" => "Amended deal",
      "endDate" => 1.year.from_now.to_date.iso8601,
      "charges" => [
        {
          "id" => charge.id,
          "billableMetric" => {"code" => billable_metric.code},
          "chargeModel" => charge.charge_model
        }
      ]
    }
  end
  let(:plan_overrides) do
    {
      "amountCents" => 80_000,
      "charges" => [
        {
          "billableMetricCode" => billable_metric.code,
          "chargeModel" => charge.charge_model,
          "properties" => {"amount" => "30"}
        }
      ]
    }
  end

  let(:billing_items) { {"plans" => [plan_item]} }
  let(:quote) do
    create(
      :quote,
      organization:,
      customer:,
      subscription: target_subscription,
      order_type: :subscription_amendment
    )
  end
  let(:quote_version) do
    create(
      :quote_version,
      :approved,
      quote:,
      organization:,
      currency: "EUR",
      billing_items:
    )
  end
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote_version:) }
  let(:order) { create(:order, organization:, customer:, order_form:, execution_mode:) }
  let(:execution_mode) { :execute_in_lago }

  # Records are resolved by id only outside api context, and CurrentContext leaks across spec
  # files (no global reset), so pin it. The order is built up front so the target subscription
  # never counts toward what an execution creates.
  before do
    CurrentContext.source = nil
    charge
    order
  end

  describe "#call" do
    context "with execute_in_lago mode" do
      it "terminates the target and replaces it on the amended plan" do
        result = nil
        expect { result = execute_service.call }.to change(Subscription, :count).by(1)

        expect(result).to be_success
        expect(target_subscription.reload).to be_terminated

        replacement = customer.subscriptions.active.sole
        expect(replacement.external_id).to eq("sub_ext_42")
        expect(replacement.name).to eq("Amended deal")
        expect(replacement.previous_subscription_id).to eq(target_subscription.id)
        expect(replacement.ending_at.to_date).to eq(1.year.from_now.to_date)

        order.reload
        expect(order.executed?).to eq(true)
        expect(order.execution_record["execution_mode"]).to eq("execute_in_lago")
        expect(order.execution_record["subscription_ids"]).to eq([replacement.id])
        expect(order.execution_record["terminated_subscription_ids"]).to eq([target_subscription.id])
        expect(order.execution_record["errors"]).to eq([])
      end

      # Without this the anniversary would move to the amendment date and every future invoice
      # boundary would shift with it.
      it "keeps the billing anchor of the terminated subscription" do
        execute_service.call

        replacement = customer.subscriptions.active.sole
        expect(replacement.subscription_at.to_i).to eq(target_subscription.subscription_at.to_i)
        expect(replacement.billing_time).to eq("anniversary")
        expect(replacement.started_at).to be_within(5.seconds).of(Time.current)
      end

      # activate_for_upgrade bills the terminated subscription and its replacement together, after
      # commit, so the amended period lands on one prorated invoice.
      it "enqueues the rotation invoice for the terminated subscription" do
        expect { execute_service.call }
          .to have_enqueued_job(BillSubscriptionJob)
          .with([target_subscription], anything, invoicing_reason: :upgrading)
      end

      it "bills the negotiated plan through an override plan" do
        execute_service.call

        overridden_plan = customer.subscriptions.active.sole.plan
        expect(overridden_plan.parent_id).to eq(plan.id)
        expect(overridden_plan.amount_cents).to eq(80_000)
        expect(overridden_plan.charges.sole.properties["amount"]).to eq("30")
      end

      # A replacement sharing the target's plan id would make ActivateService take its standalone
      # branch, leaving the target active.
      context "when triggered under the api source" do
        before { CurrentContext.source = "api" }

        it "amends the same subscription" do
          expect { execute_service.call }.to change(Subscription, :count).by(1)

          expect(target_subscription.reload).to be_terminated
          expect(customer.subscriptions.active.sole.external_id).to eq("sub_ext_42")
        end
      end

      context "without overrides" do
        let(:plan_overrides) { nil }

        it "still mints an override plan and still terminates the target" do
          execute_service.call

          expect(target_subscription.reload).to be_terminated

          replacement = customer.subscriptions.active.sole
          expect(replacement.plan.parent_id).to eq(plan.id)
          expect(replacement.plan.amount_cents).to eq(100_000)
        end
      end

      context "when the payload carries no subscription name" do
        let(:plan_payload) { super().except("subscriptionName") }

        it "keeps the name of the terminated subscription" do
          execute_service.call

          expect(customer.subscriptions.active.sole.name).to eq("Original deal")
        end
      end

      context "when the quote carries no ending date" do
        let(:plan_payload) { super().except("endDate") }

        it "keeps the term of the terminated subscription" do
          execute_service.call

          replacement = customer.subscriptions.active.sole
          expect(replacement.ending_at.to_i).to eq(target_subscription.ending_at.to_i)
        end
      end

      # The replacement starts on the anniversary date of the one it amends, so the quoted start
      # date is never read.
      context "when the quote carries a start date" do
        let(:plan_payload) { super().merge("startDate" => 6.months.from_now.to_date.iso8601) }

        it "amends the subscription anyway" do
          result = execute_service.call

          expect(result).to be_success

          replacement = customer.subscriptions.active.sole
          expect(replacement.subscription_at.to_i).to eq(target_subscription.subscription_at.to_i)
          expect(replacement.ending_at.to_date).to eq(1.year.from_now.to_date)
        end
      end

      # The trial anchors on the oldest start of the external id, which the replacement inherits.
      context "when the amended plan carries a trial" do
        let(:plan) do
          create(:plan, organization:, amount_currency: "EUR", amount_cents: 100_000, trial_period: 14)
        end

        it "does not restart it" do
          execute_service.call

          replacement = customer.subscriptions.active.sole
          expect(replacement.plan.trial_period).to eq(14)
          expect(replacement.in_trial_period?).to eq(false)
        end
      end

      context "with a pending downgrade on the target" do
        let(:pending_downgrade) do
          create(
            :subscription,
            :pending,
            customer:,
            organization:,
            plan: create(:plan, organization:, amount_cents: 10_000),
            external_id: target_subscription.external_id,
            previous_subscription_id: target_subscription.id
          )
        end

        before { pending_downgrade }

        # Left alone it would activate later and silently undo the amendment.
        it "cancels it" do
          execute_service.call

          expect(pending_downgrade.reload).to be_canceled
        end
      end

      context "with usage thresholds" do
        let(:organization) { create(:organization, premium_integrations: ["progressive_billing"]) }
        let(:plan_overrides) do
          super().merge(
            "usageThresholds" => [
              {"amountCents" => 100_000, "recurring" => false, "thresholdDisplayName" => "First"}
            ]
          )
        end

        it "creates them on the replacement, not on the overridden plan" do
          execute_service.call

          replacement = customer.subscriptions.active.sole
          expect(replacement.usage_thresholds.pluck(:amount_cents)).to eq([100_000])
          expect(replacement.plan.usage_thresholds).to be_empty
        end
      end

      # The target already paid for the running period, so terminating it mid-period has to credit
      # the days the customer will now be billed for on the amended plan.
      context "when the target subscription is paid in advance" do
        let(:target_plan) do
          create(:plan, organization:, amount_currency: "EUR", amount_cents: 50_000, pay_in_advance: true)
        end
        let(:target_subscription) do
          create(
            :subscription,
            customer:,
            organization:,
            plan: target_plan,
            name: "Original deal",
            external_id: "sub_ext_42",
            billing_time: :anniversary,
            subscription_at: Time.current.beginning_of_month - 1.month,
            started_at: Time.current.beginning_of_month - 1.month
          )
        end
        let(:date_service) do
          Subscriptions::DatesService.new_instance(
            target_subscription,
            Time.current.beginning_of_month,
            current_usage: false
          )
        end
        let(:invoice) do
          create(
            :invoice,
            customer:,
            currency: "EUR",
            sub_total_excluding_taxes_amount_cents: 50_000,
            fees_amount_cents: 50_000,
            taxes_amount_cents: 10_000,
            total_amount_cents: 60_000
          )
        end

        before do
          create(
            :invoice_subscription,
            invoice:,
            subscription: target_subscription,
            recurring: true,
            from_datetime: date_service.from_datetime,
            to_datetime: date_service.to_datetime,
            charges_from_datetime: date_service.charges_from_datetime,
            charges_to_datetime: date_service.charges_to_datetime
          )
          create(
            :fee,
            subscription: target_subscription,
            invoice:,
            amount_cents: 50_000,
            taxes_amount_cents: 10_000,
            taxes_rate: 20,
            invoiceable_type: "Subscription",
            invoiceable_id: target_subscription.id
          )
        end

        it "credits the unconsumed days of the terminated subscription" do
          expect { execute_service.call }.to change(CreditNote, :count).by(1)

          credit_note = invoice.credit_notes.sole
          expect(credit_note.credit_amount_cents).to be_positive
          expect(credit_note.reason).to eq("order_cancellation")
        end
      end

      context "with a coupon and a wallet credit" do
        let(:coupon) { create(:coupon, organization:, amount_cents: 20_000, amount_currency: "EUR") }
        let(:billing_items) do
          super().merge(
            "coupons" => [
              {
                "id" => coupon.id,
                "localId" => "ba54903c-7bd5-4d40-8d51-45a5157005ff",
                "type" => "coupon",
                "payload" => {"code" => coupon.code, "type" => "fixed_amount", "amountCents" => 20_000},
                "overrides" => {"amountCents" => 15_000}
              }
            ],
            "walletCredits" => [
              {
                "localId" => "e2a4a1a0-6f4d-4c1e-9c3f-2b1d0f8a7c11",
                "type" => "wallet_credit",
                "payload" => {
                  "name" => "Amendment credits",
                  "currency" => "EUR",
                  "rateAmount" => "1",
                  "paidCredits" => "0",
                  "grantedCredits" => "50"
                }
              }
            ]
          )
        end

        # The plan change keeps the target's entity, so the wallet has to land on the same one rather
        # than on the customer's default.
        context "when the target subscription is bound to another entity" do
          let(:target_entity) { create(:billing_entity, organization:) }
          let(:target_subscription) do
            create(:subscription, customer:, organization:, plan: target_plan, billing_entity: target_entity)
          end

          it "creates the wallet under the target's entity" do
            execute_service.call

            expect(target_entity).not_to eq(customer.billing_entity)
            expect(customer.wallets.sole.billing_entity_id).to eq(target_entity.id)
          end
        end

        it "applies them alongside the plan change" do
          execute_service.call

          applied_coupon = customer.applied_coupons.sole
          expect(applied_coupon.amount_cents).to eq(15_000)

          wallet = customer.wallets.sole
          expect(wallet.name).to eq("Amendment credits")

          order.reload
          expect(order.execution_record["applied_coupon_ids"]).to eq([applied_coupon.id])
          expect(order.execution_record["wallet_ids"]).to eq([wallet.id])
        end

        # The whole amendment is one transaction: a customer left with a terminated subscription and
        # no replacement is a billing outage, not a retryable task.
        context "when the coupon is discarded" do
          before { coupon.discard! }

          it "rolls the termination and the replacement back" do
            result = nil
            expect { result = execute_service.call }.not_to change(Subscription, :count)

            expect(result).not_to be_success
            expect(target_subscription.reload).to be_active

            order.reload
            expect(order.failed?).to eq(true)
            expect(order.execution_record["errors"]).to eq(["coupon_not_found"])
            expect(order.execution_record["subscription_ids"]).to eq([])
          end
        end
      end

      context "when the target subscription was terminated since approval" do
        before { target_subscription.mark_as_terminated! }

        it "records the failure and marks the order failed" do
          result = nil
          expect { result = execute_service.call }.not_to change(Subscription, :count)

          expect(result).not_to be_success

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["errors"]).to eq(["subscription_not_active"])
        end
      end

      context "when the quote carries a second plan" do
        let(:billing_items) { {"plans" => [plan_item, plan_item]} }

        it "records the failure and marks the order failed" do
          result = nil
          expect { result = execute_service.call }.not_to change(Subscription, :count)

          expect(result).not_to be_success

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["errors"]).to eq(["single_plan_expected"])
        end
      end

      # Lago cannot prorate a mid-period reduction, so it keeps the target running and switches at
      # the next billing day, exactly as the same plan change does through the API.
      context "when the amendment lowers the amount" do
        let(:plan_overrides) { super().merge("amountCents" => 10_000) }

        it "schedules the replacement instead of terminating the target" do
          result = nil
          expect { result = execute_service.call }.to change(Subscription, :count).by(1)

          expect(result).to be_success
          expect(target_subscription.reload).to be_active

          replacement = target_subscription.next_subscription
          expect(replacement).to be_pending
          expect(replacement.external_id).to eq("sub_ext_42")
          expect(replacement.plan.amount_cents).to eq(10_000)
          expect(replacement.ending_at.to_date).to eq(1.year.from_now.to_date)
          expect(target_subscription.downgrade_plan_date).to be > Date.current

          order.reload
          expect(order.executed?).to eq(true)
          expect(order.execution_record["subscription_ids"]).to eq([replacement.id])
          expect(order.execution_record["terminated_subscription_ids"]).to eq([])
        end

        it "invoices nothing yet" do
          expect { execute_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
        end
      end

      context "when the amendment keeps the same amount" do
        let(:plan_overrides) { super().merge("amountCents" => target_plan.amount_cents) }

        it "rotates the subscription right away" do
          execute_service.call

          expect(target_subscription.reload).to be_terminated
          expect(customer.subscriptions.active.sole.plan.amount_cents).to eq(target_plan.amount_cents)
        end
      end

      context "when the plan is gone" do
        before { plan.discard! }

        it "records the failure and marks the order failed" do
          result = execute_service.call

          expect(result).not_to be_success

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["errors"]).to eq(["plan_not_found"])
        end
      end

      context "when the plan change fails" do
        let(:failed_result) do
          Subscriptions::CreateService::Result.new.tap do |failed|
            failed.single_validation_failure!(field: :ending_at, error_code: "invalid_date")
          end
        end

        before do
          allow(Subscriptions::CreateService).to receive(:call!).and_raise(failed_result.error)
        end

        it "records the failure and leaves the target active" do
          result = execute_service.call

          expect(result).not_to be_success
          expect(target_subscription.reload).to be_active

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["executed_at"]).to be_nil
          expect(order.execution_record["errors"]).to eq(["invalid_date"])
        end
      end
    end

    context "with order_only mode" do
      let(:execution_mode) { :order_only }

      it "marks the order executed without touching the subscription" do
        expect { execute_service.call }.not_to change(Subscription, :count)

        expect(target_subscription.reload).to be_active

        order.reload
        expect(order.executed?).to eq(true)
        expect(order.execution_record["subscription_ids"]).to eq([])
        expect(order.execution_record["terminated_subscription_ids"]).to eq([])
      end

      it "produces an order.executed activity log" do
        execute_service.call

        expect(Utils::ActivityLog).to have_produced("order.executed").after_commit.with(order)
      end
    end
  end
end
