# frozen_string_literal: true

require "rails_helper"

describe "Wallet ongoing balance with a draft invoice awaiting provider taxes", :premium do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
  let(:tax_integration) { create(:anrok_integration, organization:) }
  let(:tax_integration_customer) { create(:anrok_customer, integration: tax_integration, customer:) }
  let(:anrok_client) { instance_double(LagoHttpClient::Client) }
  let(:anrok_draft_endpoint) { "https://api.nango.dev/v1/anrok/draft_invoices" }
  let(:success_body_template) { JSON.parse(File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json"))) }
  let(:plan_code) { "monthly_in_arrears" }
  let(:external_subscription_id) { "sub-#{SecureRandom.hex(4)}" }

  before do
    tax_integration_customer
    allow(LagoHttpClient::Client).to receive(:new).and_call_original
    allow(LagoHttpClient::Client).to receive(:new).with(anrok_draft_endpoint, anything).and_return(anrok_client)
    allow(anrok_client).to receive(:post_with_response) do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(success_body_for(customer.invoices.draft.sole))
      response
    end
  end

  # Anrok answers for the fees it receives, so its fee entry must carry the real draft fee id.
  def success_body_for(invoice)
    body = success_body_template.deep_dup
    body["succeededInvoices"].first["fees"].first["item_id"] = invoice.fees.sole.id
    body.to_json
  end

  it "reserves the draft in the ongoing balance once the provider taxes are pulled" do
    travel_to(Time.zone.parse("2025-12-01T10:00:00")) do
      create_plan({
        name: "Monthly in arrears",
        code: plan_code,
        interval: "monthly",
        amount_cents: 1_000,
        amount_currency: "EUR",
        pay_in_advance: false
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
        granted_credits: "100.00",
        invoice_requires_successful_payment: false
      })
    end

    wallet = customer.wallets.active.sole
    expect(wallet.balance_cents).to eq(10_000)

    travel_to(Time.zone.parse("2026-01-01T10:00:00")) do
      # Billing run: the draft waits for Anrok, the pull is held back.
      Clock::SubscriptionsBillerJob.perform_later
      perform_all_enqueued_jobs(except: [Invoices::ProviderTaxes::PullTaxesAndApplyJob])

      invoice = customer.invoices.draft.sole
      expect(invoice.tax_status).to eq("pending")
      expect(invoice.total_amount_cents).to eq(0)

      # Wallet refresh before the pull leaves the draft out (total still 0).
      Clock::RefreshWalletsOngoingBalanceJob.perform_later
      perform_all_enqueued_jobs(except: [Invoices::ProviderTaxes::PullTaxesAndApplyJob])

      wallet.reload
      expect(wallet.ongoing_usage_balance_cents).to eq(0)
      expect(wallet.ongoing_balance_cents).to eq(wallet.balance_cents)
      expect(customer.reload.awaiting_wallet_refresh).to be(false)

      # Provider tax pull sets the draft total and flags the customer.
      perform_all_enqueued_jobs(only: [Invoices::ProviderTaxes::PullTaxesAndApplyJob])

      invoice.reload
      expect(invoice).to be_draft
      expect(invoice.tax_status).to eq("succeeded")
      expect(invoice.total_amount_cents).to eq(1_000 + 990) # subscription fee + Anrok tax_amount_cents from success_response.json
      expect(customer.reload.awaiting_wallet_refresh).to be(true)

      # Clock refresh reserves the draft in the ongoing balance.
      perform_wallet_refresh

      wallet.reload
      expect(wallet.ongoing_usage_balance_cents).to eq(1_000 + 990) # subscription fee + Anrok tax_amount_cents
      expect(wallet.ongoing_balance_cents).to eq(10_000 - (1_000 + 990)) # granted credits - draft total
      expect(wallet.balance_cents).to eq(10_000)
      expect(customer.reload.awaiting_wallet_refresh).to be(false)
    end
  end
end
