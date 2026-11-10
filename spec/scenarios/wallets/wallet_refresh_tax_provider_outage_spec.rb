# frozen_string_literal: true

require "rails_helper"

describe "Wallet refresh during a tax provider outage", :premium do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:tax_integration) { create(:anrok_integration, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:nango_action_endpoint) { "https://api.nango.dev/action/trigger" }
  let(:plan_code) { "monthly_usage" }
  let(:external_subscription_id) { "sub-#{SecureRandom.hex(4)}" }

  # The next clock run depends on the uniqueness lock the give-up releases, so locks are enforced.
  around do |example|
    ActiveJob::Uniqueness.reset_manager!
    example.run
  ensure
    Customers::RefreshWalletJob.unlock!
    Clock::RefreshWalletsOngoingBalanceJob.unlock!
    ActiveJob::Uniqueness.test_mode!
  end

  before do
    create(:anrok_customer, integration: tax_integration, customer:)
    create(
      :netsuite_collection_mapping,
      integration: tax_integration,
      mapping_type: :fallback_item,
      settings: {external_id: "1", external_account_code: "11", external_name: ""}
    )
  end

  # Anrok answers for the fees it receives: each requested line is taxed at 10%.
  def anrok_draft_answer(request)
    fees = JSON.parse(request.body).dig("input", 0, "fees").map do |fee|
      tax_amount_cents = (fee["amount_cents"].to_i * 0.1).round

      {
        item_key: fee["item_key"],
        item_id: fee["item_id"],
        item_code: fee["item_code"],
        amount_cents: fee["amount_cents"],
        tax_amount_cents:,
        tax_breakdown: [{name: "GST/HST", rate: "0.10", tax_amount: tax_amount_cents, type: "tax"}]
      }
    end

    {succeededInvoices: [{id: "inv_1", fees:}], failedInvoices: []}.to_json
  end

  it "keeps the customer flagged through the outage and refreshes the wallet on the next clock run" do
    travel_to(Time.zone.parse("2026-03-01T10:00:00")) do
      create_plan({
        name: "Monthly usage",
        code: plan_code,
        interval: "monthly",
        amount_cents: 0,
        amount_currency: "EUR",
        pay_in_advance: false,
        charges: [
          {billable_metric_id: billable_metric.id, charge_model: "standard", properties: {amount: "3"}}
        ]
      })

      create_subscription({
        external_customer_id: customer.external_id,
        external_id: external_subscription_id,
        plan_code:,
        billing_time: "calendar"
      })

      create_wallet({
        external_customer_id: customer.external_id,
        rate_amount: "1",
        currency: "EUR",
        granted_credits: "10.00",
        invoice_requires_successful_payment: false
      })
    end

    wallet = customer.wallets.active.sole
    expect(wallet.balance_cents).to eq(1_000)
    expect(wallet.credits_balance).to eq(10.0)
    expect(wallet.ongoing_balance_cents).to eq(1_000)

    # Tax provider outage: every draft tax request answers 503 with an empty body.
    stub_request(:post, nango_action_endpoint).to_return(status: 503, body: "")

    travel_to(Time.zone.parse("2026-03-10T10:00:00")) do
      create_event({
        code: billable_metric.code,
        external_subscription_id:,
        properties: {}
      })

      expect(customer.reload.awaiting_wallet_refresh).to be(true)

      # The refresh job retries the 503 then gives up without a dead job.
      expect do
        Customers::RefreshWalletJob.perform_later(customer)
        perform_all_enqueued_jobs
      end.not_to raise_error

      expect(a_request(:post, nango_action_endpoint)).to have_been_made.at_least_times(6)
      expect(customer.reload.awaiting_wallet_refresh).to be(true)
      expect(customer.error_details.tax_error).to be_empty
      expect(wallet.reload.ongoing_balance_cents).to eq(1_000)
      expect(wallet.credits_ongoing_balance).to eq(10.0)
    end

    # The provider answers again.
    stub_request(:post, nango_action_endpoint).to_return(->(request) { {status: 200, body: anrok_draft_answer(request)} })

    travel_to(Time.zone.parse("2026-03-10T10:05:00")) do
      # The next clock run can enqueue the refresh only because the give-up released the uniqueness lock.
      expect { Clock::RefreshWalletsOngoingBalanceJob.perform_now }
        .to have_enqueued_job(Customers::RefreshWalletJob).with(customer)

      perform_all_enqueued_jobs

      wallet.reload
      expect(wallet.ongoing_usage_balance_cents).to eq(300 + 30) # 1 event x 3 EUR usage fee + 10% provider tax
      expect(wallet.ongoing_balance_cents).to eq(1_000 - (300 + 30)) # balance - ongoing usage
      expect(wallet.credits_ongoing_balance).to eq(6.7) # 670 cents at rate 1
      expect(wallet.balance_cents).to eq(1_000)
      expect(customer.reload.awaiting_wallet_refresh).to be(false)
    end
  end
end
