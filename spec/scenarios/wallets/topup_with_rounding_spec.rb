# frozen_string_literal: true

require "rails_helper"

describe "Wallet Transaction with rounding", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  around { |test| lago_premium!(&test) }

  it "rounds the amount field when handling paid_credits" do
    create_wallet({
      external_customer_id: customer.external_id,
      rate_amount: "1",
      name: "Wallet1",
      currency: "EUR",
      invoice_requires_successful_payment: false
    })
    wallet = customer.wallets.sole

    expect(wallet.rate_amount).to eq(1)

    create_wallet_transaction({
      wallet_id: wallet.id,
      paid_credits: "17.9699999999999988631316",
      invoice_requires_successful_payment: false
    })

    wt = WalletTransaction.find json[:wallet_transactions].first[:lago_id]
    expect(wt.status).to eq "pending"
    expect(wt.transaction_status).to eq "purchased"
    expect(wt.invoice_requires_successful_payment).to be false
    expect(wt.credit_amount).to eq(17.97)
    expect(wt.amount).to eq(17.97)

    # Customer does not have a payment_provider set yet
    invoice = customer.invoices.credit.sole
    expect(invoice.status).to eq "finalized"
    expect(invoice.payment_status).to eq "pending"
    expect(invoice.total_amount_cents).to eq 1797

    # mark invoice as paid
    update_invoice(invoice, {payment_status: "succeeded"})
    perform_all_enqueued_jobs

    wt.reload
    expect(wt.status).to eq "settled"
    expect(wt.settled_at).not_to be_nil

    wallet.reload
    expect(wallet.credits_balance).to eq 17.97
  end

  it "does not apply rounding handling granted_credits" do
    create_wallet({
      external_customer_id: customer.external_id,
      rate_amount: "1",
      name: "Wallet1",
      currency: "EUR",
      invoice_requires_successful_payment: false
    })
    wallet = customer.wallets.sole

    expect(wallet.rate_amount).to eq(1)

    create_wallet_transaction({
      wallet_id: wallet.id,
      granted_credits: "17.9699999999999988631316",
      invoice_requires_successful_payment: false
    })

    wt = WalletTransaction.find json[:wallet_transactions].first[:lago_id]
    expect(wt.status).to eq "settled"
    expect(wt.transaction_status).to eq "granted"
    expect(wt.invoice_requires_successful_payment).to be false
    expect(wt.credit_amount).to eq(17.96999)
    expect(wt.amount).to eq(17.97)

    perform_all_enqueued_jobs

    wallet.reload
    expect(wallet.credits_balance).to eq 17.96999
  end
end
