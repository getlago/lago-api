# frozen_string_literal: true

require "rails_helper"

describe "Invoice Preview Scenarios", :premium do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["preview"]) }

  context "when charge has a spending minimum" do
    let(:customer) { create(:customer, organization:) }
    let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 23) }
    let(:plan) { create(:plan, organization:, amount_cents: 0) }
    let(:billable_metric) { create(:sum_billable_metric, organization:) }
    let(:charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        min_amount_cents: 233_700,
        properties: {amount: "1"}
      )
    end
    let(:subscription) do
      create(
        :subscription,
        customer:,
        plan:,
        started_at: DateTime.parse("2026-03-01"),
        subscription_at: DateTime.parse("2026-03-01"),
        ending_at: DateTime.parse("2026-03-31"),
        billing_time: :calendar
      )
    end

    before do
      charge
      tax

      create(
        :event,
        organization:,
        customer:,
        subscription:,
        code: billable_metric.code,
        timestamp: DateTime.parse("2026-03-02 10:00:00"),
        properties: {billable_metric.field_name => 16.25}
      )
    end

    it "computes fees_amount_cents based on the correct billing period duration" do
      travel_to(DateTime.parse("2026-03-03 12:00:00")) do
        # First call current_usage to populate the charge cache with a fee
        # whose timestamp is March 3 (mid-period, not the billing boundary).
        fetch_current_usage(customer:, subscription:)

        # Now call invoice preview. The cache returns the fee from current_usage
        # which has a stale timestamp (March 3). The true-up calculation should
        # still use the correct billing period duration (31 days for March).
        #
        # Expected:
        #   charge fee = 16.25 units * 1 EUR = 1625 cents
        #   min_amount = 233700 cents (full March, no proration)
        #   true_up    = 233700 - 1625 = 232075 cents
        #   total fees = 233700 cents
        #   tax 23%    = 53751 cents
        #   total      = 287451 cents
        post_with_token(
          organization,
          "/api/v1/invoices/preview",
          {
            customer: {external_id: customer.external_id},
            subscriptions: {external_ids: [subscription.external_id]}
          }
        )

        expect(response).to have_http_status(:success)
        expect(json[:invoice]).to include(
          fees_amount_cents: 233_700,
          taxes_amount_cents: 53_751,
          total_amount_cents: 287_451
        )
      end
    end
  end

  context "when wallet has allowed_fee_types restriction" do
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, amount_cents: 2_000) }
    let(:wallet) { create(:wallet, customer:, organization:, balance_cents: 500, credits_balance: 5.0, allowed_fee_types: %w[fixed_charge]) }
    let(:preview_params) do
      {
        customer: {external_id: customer.external_id},
        plan_code: plan.code,
        billing_time: "calendar"
      }
    end

    context "when the preview invoice contains only subscription fees" do
      before { wallet }

      it "does not calculate wallet credit to subscription fees" do
        travel_to(DateTime.parse("2026-03-01 12:00:00")) do
          post_with_token(organization, "/api/v1/invoices/preview", preview_params)

          expect(response).to have_http_status(:success)
          expect(json[:invoice]).to include(
            fees_amount_cents: 2_000,
            prepaid_credit_amount_cents: 0,
            total_amount_cents: 2_000
          )
        end
      end
    end

    context "when the preview invoice contains a mix of matching and non-matching fees" do
      let(:fixed_charge) { create(:fixed_charge, plan:, units: 1, charge_model: "standard", properties: {amount: "3"}) }

      before do
        fixed_charge
        wallet
      end

      it "calculates wallet credit only to matching fee types, capped at the fee amount" do
        travel_to(DateTime.parse("2026-03-01 12:00:00")) do
          # subscription fee = 2000 cents (full March, calendar billing)
          # fixed_charge fee = 1 unit * 3 EUR = 300 cents
          # wallet 500 cents is restricted to fixed_charge fees,
          # so it can only consume against the 300 cents fixed_charge fee
          # prepaid_credit_amount_cents = 300, NOT 500
          post_with_token(organization, "/api/v1/invoices/preview", preview_params)

          expect(response).to have_http_status(:success)
          expect(json[:invoice]).to include(
            fees_amount_cents: 2_300,
            prepaid_credit_amount_cents: 300,
            total_amount_cents: 2_000
          )
          expect(wallet.reload.balance_cents).to eq(500)
        end
      end
    end
  end

  context "when a downgrade is scheduled" do
    let(:customer) { create(:customer, organization:) }
    let(:current_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 12_900)
    end
    let(:downgrade_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 5_000)
    end

    it "serializes the pending plan's first period, matching its fee boundaries", transaction: false do
      travel_to(DateTime.parse("2026-03-03T08:00:00Z")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: current_plan.code,
            billing_time: "anniversary",
            subscription_at: "2026-03-03T08:00:00Z"
          }
        )
      end

      # Current period runs Jun 3 to Jul 2, so the downgrade starts a new period on Jul 3.
      travel_to(DateTime.parse("2026-06-04T10:00:00Z")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: downgrade_plan.code,
            billing_time: "anniversary"
          }
        )

        subscription = customer.subscriptions.active.first
        expect(subscription.plan).to eq(current_plan)
        expect(subscription.next_subscription.plan).to eq(downgrade_plan)

        post_with_token(
          organization,
          "/api/v1/invoices/preview",
          {
            customer: {external_id: customer.external_id},
            subscriptions: {external_ids: [subscription.external_id]}
          }
        )

        expect(response).to have_http_status(:success)

        pending_plan = json[:invoice][:subscriptions].find { |s| s[:plan_code] == downgrade_plan.code }
        expect(pending_plan).to be_present
        expect(pending_plan[:started_at]).to eq("2026-07-03T00:00:00.000Z")
        expect(pending_plan[:current_billing_period_started_at]).to eq("2026-07-03T00:00:00Z")
        expect(pending_plan[:current_billing_period_ending_at]).to eq("2026-08-02T23:59:59Z")
        expect(pending_plan[:current_billing_period_started_at])
          .not_to eq(pending_plan[:current_billing_period_ending_at])

        pending_fee = json[:invoice][:fees].find do |fee|
          fee[:item][:type] == "subscription" && fee[:item][:code] == downgrade_plan.code
        end
        expect(pending_fee).to be_present
        expect(Time.zone.parse(pending_plan[:current_billing_period_started_at])).to eq(Time.zone.parse(pending_fee[:from_date]))
        expect(Time.zone.parse(pending_plan[:current_billing_period_ending_at])).to eq(Time.zone.parse(pending_fee[:to_date]))
      end
    end
  end

  context "when an active and a pending subscription are previewed together" do
    let(:customer) { create(:customer, organization:) }
    let(:active_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 10_000)
    end
    let(:pending_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 1_000)
    end

    it "returns the fees of both subscriptions", transaction: false do
      travel_to(DateTime.parse("2026-10-01T00:00:00Z")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "active-sub",
            plan_code: active_plan.code,
            billing_time: "calendar"
          }
        )
      end

      travel_to(DateTime.parse("2026-11-24T10:00:00Z")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "pending-sub",
            plan_code: pending_plan.code,
            billing_time: "calendar",
            subscription_at: "2026-12-01T00:00:00Z",
            plan_overrides: {amount_cents: 300_000}
          }
        )
        expect(customer.subscriptions.find_by(external_id: "pending-sub")).to be_pending

        post_with_token(
          organization,
          "/api/v1/invoices/preview",
          {
            customer: {external_id: customer.external_id},
            subscriptions: {external_ids: ["active-sub", "pending-sub"]}
          }
        )

        expect(response).to have_http_status(:success)

        subscription_fees = json[:invoice][:fees]
          .select { |fee| fee[:item][:type] == "subscription" }
          .map { |fee| [fee[:external_subscription_id], fee[:amount_cents], fee[:from_date], fee[:to_date]] }
        expect(subscription_fees).to match_array(
          [
            ["active-sub", 10_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"],
            # overridden price, 31 of 31 days of December
            ["pending-sub", 300_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"]
          ]
        )
        expect(json[:invoice]).to include(
          fees_amount_cents: 310_000, # 10_000 (active) + 300_000 (pending)
          issuing_date: "2026-12-01"
        )
        expect(json[:invoice][:subscriptions].map { |s| s[:external_id] })
          .to match_array(["active-sub", "pending-sub"])
      end
    end
  end

  context "when an active subscription is previewed with other pending subscriptions" do
    let(:customer) { create(:customer, organization:) }
    let(:active_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 10_000)
    end
    let(:pending_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: pending_pay_in_advance, amount_cents: 1_000)
    end
    let(:pending_pay_in_advance) { true }
    let(:pending_subscription_at) { "2026-12-01T00:00:00Z" }

    def preview_active_and_pending
      travel_to(DateTime.parse("2026-10-01T00:00:00Z")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "active-sub",
            plan_code: active_plan.code,
            billing_time: "calendar"
          }
        )
      end

      travel_to(DateTime.parse("2026-11-24T10:00:00Z")) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "pending-sub",
            plan_code: pending_plan.code,
            billing_time: "calendar",
            subscription_at: pending_subscription_at,
            plan_overrides: {amount_cents: 300_000}
          }
        )
        expect(customer.subscriptions.find_by(external_id: "pending-sub")).to be_pending

        post_with_token(
          organization,
          "/api/v1/invoices/preview",
          {
            customer: {external_id: customer.external_id},
            subscriptions: {external_ids: ["pending-sub", "active-sub"]}
          }
        )
      end
    end

    def subscription_fees
      json[:invoice][:fees]
        .select { |fee| fee[:item][:type] == "subscription" }
        .map { |fee| [fee[:external_subscription_id], fee[:amount_cents], fee[:from_date], fee[:to_date]] }
    end

    context "when the customer has an invoice grace period" do
      # keep_anchor makes the recurring rule (2026-12-01) differ from the grace period (2026-12-04)
      let(:customer) do
        create(
          :customer,
          organization:,
          invoice_grace_period: 3,
          subscription_invoice_issuing_date_anchor: "next_period_start",
          subscription_invoice_issuing_date_adjustment: "keep_anchor"
        )
      end

      it "issues the invoice with the recurring rule of the active subscription", transaction: false do
        preview_active_and_pending

        expect(response).to have_http_status(:success)
        expect(subscription_fees).to match_array(
          [
            ["active-sub", 10_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"],
            ["pending-sub", 300_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"]
          ]
        )
        expect(json[:invoice]).to include(
          fees_amount_cents: 310_000, # 10_000 (active) + 300_000 (pending)
          issuing_date: "2026-12-01"
        )
      end
    end

    context "when the pending subscription is paid in arrears and starts on the billing date" do
      let(:pending_pay_in_advance) { false }

      it "returns only the fee of the active subscription", transaction: false do
        preview_active_and_pending

        expect(response).to have_http_status(:success)
        expect(subscription_fees).to eq(
          [["active-sub", 10_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"]]
        )
        expect(json[:invoice]).to include(fees_amount_cents: 10_000, issuing_date: "2026-12-01")
        expect(json[:invoice][:subscriptions].map { |s| s[:external_id] }).to eq(["active-sub"])
      end
    end

    context "when the pending subscription starts after the billing date" do
      let(:pending_subscription_at) { "2027-01-15T00:00:00Z" }

      it "returns only the fee of the active subscription", transaction: false do
        preview_active_and_pending

        expect(response).to have_http_status(:success)
        expect(subscription_fees).to eq(
          [["active-sub", 10_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"]]
        )
        expect(json[:invoice]).to include(fees_amount_cents: 10_000, issuing_date: "2026-12-01")
        expect(json[:invoice][:subscriptions].map { |s| s[:external_id] }).to eq(["active-sub"])
      end
    end
  end

  context "when several pending subscriptions are previewed together" do
    let(:customer) { create(:customer, organization:) }
    let(:advance_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 300_000)
    end
    let(:other_advance_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 5_000)
    end
    let(:arrears_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: false, amount_cents: 5_000)
    end

    # Creates the subscriptions in the given order (one minute apart), then previews them.
    def preview_pending(subscriptions)
      subscriptions.each_with_index do |(external_id, plan), index|
        travel_to(DateTime.parse("2026-11-24T10:00:00Z") + index.minutes) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id:,
              plan_code: plan.code,
              billing_time: "calendar",
              subscription_at: "2026-12-01T00:00:00Z"
            }
          )
        end
      end

      travel_to(DateTime.parse("2026-11-24T11:00:00Z")) do
        post_with_token(
          organization,
          "/api/v1/invoices/preview",
          {
            customer: {external_id: customer.external_id},
            subscriptions: {external_ids: subscriptions.map(&:first)}
          }
        )
      end
    end

    def subscription_fees
      json[:invoice][:fees]
        .select { |fee| fee[:item][:type] == "subscription" }
        .map { |fee| [fee[:external_subscription_id], fee[:amount_cents], fee[:from_date], fee[:to_date]] }
    end

    context "when both are paid in advance" do
      it "returns the fee of each subscription", transaction: false do
        preview_pending([["pending-b", advance_plan], ["pending-c", other_advance_plan]])

        expect(response).to have_http_status(:success)
        expect(subscription_fees).to match_array(
          [
            ["pending-b", 300_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"],
            ["pending-c", 5_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"]
          ]
        )
        expect(json[:invoice]).to include(
          fees_amount_cents: 305_000, # 300_000 (B) + 5_000 (C)
          issuing_date: "2026-12-01"
        )
        expect(json[:invoice][:subscriptions].map { |s| s[:external_id] })
          .to match_array(["pending-b", "pending-c"])
        expect(customer.subscriptions.where(external_id: ["pending-b", "pending-c"]))
          .to all(have_attributes(status: "pending", started_at: nil))
      end
    end

    context "when both are paid in arrears" do
      it "bills each of them for December on 2027-01-01", transaction: false do
        preview_pending([["pending-d", arrears_plan], ["pending-e", arrears_plan]])

        expect(response).to have_http_status(:success)
        expect(subscription_fees).to match_array(
          [
            ["pending-d", 5_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"],
            ["pending-e", 5_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"]
          ]
        )
        expect(json[:invoice]).to include(
          fees_amount_cents: 10_000, # 5_000 (D) + 5_000 (E)
          issuing_date: "2027-01-01" # end of the first period (2026-12-31) + 1 day
        )
      end
    end

    context "when one is paid in advance and the other in arrears" do
      shared_examples "a preview of the pay in advance subscription only" do
        it "bills the pay in advance subscription on its start date and leaves the other out", transaction: false do
          preview_pending(subscriptions)

          expect(response).to have_http_status(:success)
          expect(subscription_fees).to eq(
            [["pending-b", 300_000, "2026-12-01T00:00:00+00:00", "2026-12-31T23:59:59+00:00"]]
          )
          expect(json[:invoice]).to include(fees_amount_cents: 300_000, issuing_date: "2026-12-01")
          expect(json[:invoice][:subscriptions].map { |s| s[:external_id] }).to eq(["pending-b"])
        end
      end

      context "when the pay in advance subscription is created first" do
        let(:subscriptions) { [["pending-b", advance_plan], ["pending-d", arrears_plan]] }

        it_behaves_like "a preview of the pay in advance subscription only"
      end

      context "when the pay in arrears subscription is created first" do
        let(:subscriptions) { [["pending-d", arrears_plan], ["pending-b", advance_plan]] }

        it_behaves_like "a preview of the pay in advance subscription only"
      end
    end
  end
end
