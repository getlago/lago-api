# frozen_string_literal: true

require "rails_helper"

# Orders::ExecuteService only dispatches here on a premium license, and plan overrides plus
# recurring rules are premium-gated downstream.
RSpec.describe Orders::SubscriptionCreation::ExecuteService, :premium do
  subject(:execute_service) { described_class.new(order:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:, currency: "EUR") }
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
      "subscriptionExternalId" => "sub_ext_42",
      "subscriptionName" => "Enterprise deal",
      "billingTime" => "anniversary",
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
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }
  let(:quote_version) do
    create(
      :quote_version,
      :approved,
      quote:,
      organization:,
      currency: "EUR",
      start_date: Date.current,
      end_date: 1.year.from_now.to_date,
      billing_items:
    )
  end
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote_version:) }
  let(:order) { create(:order, organization:, customer:, order_form:, execution_mode:) }
  let(:execution_mode) { :execute_in_lago }

  # Records are resolved by id only outside api context, and CurrentContext leaks across spec
  # files (no global reset), so pin it.
  before do
    CurrentContext.source = nil
    charge
  end

  describe "#call" do
    context "with execute_in_lago mode" do
      it "creates the subscription and marks the order executed" do
        result = nil
        expect { result = execute_service.call }.to change(Subscription, :count).by(1)

        expect(result).to be_success

        subscription = customer.subscriptions.sole
        expect(subscription.external_id).to eq("sub_ext_42")
        expect(subscription.name).to eq("Enterprise deal")
        expect(subscription.billing_time).to eq("anniversary")
        expect(subscription.ending_at.to_date).to eq(quote_version.end_date)

        order.reload
        expect(order.executed?).to eq(true)
        expect(order.executed_at).to be_present
        expect(order.execution_record["executed_at"]).to be_present
        expect(order.execution_record["execution_mode"]).to eq("execute_in_lago")
        expect(order.execution_record["invoice_id"]).to be_nil
        expect(order.execution_record["subscription_ids"]).to eq([subscription.id])
        expect(order.execution_record["errors"]).to eq([])
      end

      it "bills the negotiated plan through an override plan" do
        execute_service.call

        overridden_plan = customer.subscriptions.sole.plan
        expect(overridden_plan.parent_id).to eq(plan.id)
        expect(overridden_plan.amount_cents).to eq(80_000)
        expect(overridden_plan.charges.sole.properties["amount"]).to eq("30")
      end

      context "without overrides" do
        let(:plan_overrides) { nil }

        it "subscribes to the catalog plan" do
          execute_service.call

          expect(customer.subscriptions.sole.plan).to eq(plan)
        end
      end

      context "when the payload carries no external id" do
        let(:plan_payload) { super().except("subscriptionExternalId") }

        it "generates one" do
          execute_service.call

          expect(customer.subscriptions.sole.external_id).to be_present
        end
      end

      context "when the payload carries dates" do
        let(:plan_payload) do
          super().merge("startDate" => 2.days.from_now.iso8601, "endDate" => 2.years.from_now.iso8601)
        end

        it "uses them over the version dates" do
          execute_service.call

          subscription = customer.subscriptions.sole
          expect(subscription.subscription_at.to_date).to eq(2.days.from_now.to_date)
          expect(subscription.ending_at.to_date).to eq(2.years.from_now.to_date)
        end
      end

      context "when the payload carries a payment method" do
        let(:payment_method) { create(:payment_method, organization:, customer:) }
        let(:plan_payload) { super().merge("paymentMethodId" => payment_method.id) }

        it "attaches it to the subscription" do
          execute_service.call

          expect(customer.subscriptions.sole.payment_method_id).to eq(payment_method.id)
        end
      end

      context "with several plans" do
        let(:other_plan) { create(:plan, organization:, amount_currency: "EUR") }
        let(:billing_items) do
          {
            "plans" => [
              plan_item,
              {
                "id" => other_plan.id,
                "type" => "plan",
                "payload" => {"code" => other_plan.code, "subscriptionExternalId" => "sub_ext_43"}
              }
            ]
          }
        end

        it "creates one subscription per plan" do
          expect { execute_service.call }.to change(Subscription, :count).by(2)

          order.reload
          expect(order.execution_record["subscription_ids"].count).to eq(2)
        end
      end

      context "when the overridden charge is gone from the plan" do
        before { charge.discard! }

        it "records the failure and marks the order failed" do
          result = nil
          expect { result = execute_service.call }.not_to change(Subscription, :count)

          expect(result).not_to be_success

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["errors"]).to eq(["charge_not_found"])
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

      context "when the subscription creation fails" do
        let(:failed_result) do
          Subscriptions::CreateService::Result.new.tap do |failed|
            failed.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
          end
        end

        before do
          allow(Subscriptions::CreateService).to receive(:call!).and_raise(failed_result.error)
        end

        it "records the failure and marks the order failed" do
          result = execute_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["executed_at"]).to be_nil
          expect(order.execution_record["subscription_ids"]).to eq([])
          expect(order.execution_record["errors"]).to eq(["currencies_does_not_match"])
        end
      end

      context "with a coupon" do
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
            ]
          )
        end

        it "applies the negotiated amount" do
          expect { execute_service.call }.to change(AppliedCoupon, :count).by(1)

          applied_coupon = customer.applied_coupons.sole
          expect(applied_coupon.coupon).to eq(coupon)
          expect(applied_coupon.amount_cents).to eq(15_000)

          order.reload
          expect(order.execution_record["applied_coupon_ids"]).to eq([applied_coupon.id])
        end

        context "when the coupon is discarded" do
          before { coupon.discard! }

          it "records the failure and marks the order failed" do
            result = nil
            expect { result = execute_service.call }.not_to change(AppliedCoupon, :count)

            expect(result).not_to be_success

            order.reload
            expect(order.failed?).to eq(true)
            expect(order.execution_record["errors"]).to eq(["coupon_not_found"])
          end
        end
      end

      context "with a wallet credit" do
        let(:billing_items) do
          super().merge(
            "walletCredits" => [
              {
                "localId" => "d9169d94-b322-4d70-a2b1-9e6a58e3f74a",
                "type" => "wallet_credit",
                "payload" => wallet_credit_payload
              }
            ]
          )
        end
        let(:wallet_credit_payload) do
          {
            "name" => "Prepaid credits",
            "currency" => "EUR",
            "rateAmount" => "1",
            "paidCredits" => "100",
            "grantedCredits" => "10",
            "appliesTo" => {"feeTypes" => ["charge"], "billableMetricCodes" => [billable_metric.code]}
          }
        end

        it "creates the wallet with its limitation" do
          expect { execute_service.call }.to change(Wallet, :count).by(1)

          wallet = customer.wallets.sole
          expect(wallet.name).to eq("Prepaid credits")
          expect(wallet.rate_amount).to eq(1)
          expect(wallet.allowed_fee_types).to eq(["charge"])
          expect(wallet.billable_metrics).to eq([billable_metric])

          order.reload
          expect(order.execution_record["wallet_ids"]).to eq([wallet.id])
        end

        context "with a recurring rule" do
          let(:wallet_credit_payload) do
            super().merge(
              "recurringTransactionRules" => [
                {
                  "trigger" => "interval",
                  "interval" => "monthly",
                  "method" => "target",
                  "targetOngoingBalance" => "500",
                  "grantsTargetTopUp" => true,
                  "transactionName" => "Monthly refill"
                }
              ]
            )
          end

          it "creates the rule" do
            expect { execute_service.call }.to change(RecurringTransactionRule, :count).by(1)

            rule = customer.wallets.sole.recurring_transaction_rules.sole
            expect(rule.trigger).to eq("interval")
            expect(rule.interval).to eq("monthly")
            expect(rule.method).to eq("target")
            expect(rule.target_ongoing_balance).to eq(500)
            expect(rule.grants_target_top_up).to eq(true)
            expect(rule.transaction_name).to eq("Monthly refill")
          end
        end

        context "when a limitation metric no longer exists" do
          let(:wallet_credit_payload) do
            super().merge("appliesTo" => {"billableMetricCodes" => ["gone_metric"]})
          end

          it "records the failure and marks the order failed" do
            result = nil
            expect { result = execute_service.call }.not_to change(Wallet, :count)

            expect(result).not_to be_success

            order.reload
            expect(order.failed?).to eq(true)
            expect(order.execution_record["errors"]).to eq(["billable_metric_not_found"])
          end
        end
      end
    end

    context "with order_only mode" do
      let(:execution_mode) { :order_only }

      it "marks the order executed without creating anything" do
        result = nil
        expect { result = execute_service.call }.not_to change(Subscription, :count)

        expect(result).to be_success

        order.reload
        expect(order.executed?).to eq(true)
        expect(order.execution_record["execution_mode"]).to eq("order_only")
        expect(order.execution_record["subscription_ids"]).to eq([])
        expect(order.execution_record["errors"]).to eq([])
      end
    end

    context "when the order is already executed" do
      let(:order) { create(:order, :executed_in_lago, organization:, customer:, order_form:) }

      it "is idempotent and does nothing" do
        result = nil
        expect { result = execute_service.call }.not_to change(Subscription, :count)

        expect(result).to be_success
        expect(result.order).to eq(order)
      end
    end

    context "when the order has no execution_mode" do
      let(:order) { create(:order, organization:, customer:, order_form:, execution_mode: nil) }

      it "returns a validation failure without touching the order" do
        result = nil
        expect { result = execute_service.call }.not_to change(Subscription, :count)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:execution_mode]).to eq(["value_is_mandatory"])

        order.reload
        expect(order.executed?).to eq(false)
        expect(order.execution_record).to eq({})
      end
    end
  end
end
