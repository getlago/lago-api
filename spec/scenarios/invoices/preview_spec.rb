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
end
