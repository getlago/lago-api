# frozen_string_literal: true

require "rails_helper"

describe "Top-ups paid with a shared payment token", :premium do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, currency: "USD") }
  let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_1") }
  let(:add_on) { create(:add_on, organization:, amount_cents: 500, amount_currency: "USD") }
  let(:charged) { [] }

  before do
    create(:stripe_customer, customer:, payment_provider: stripe_provider, provider_customer_id: "cus_1", provider_payment_methods: %w[shared_payment_token])
    customer.update!(payment_provider: "stripe", payment_provider_code: stripe_provider.code)

    allow(Stripe::PaymentIntent).to receive(:create) do |payload, _opts|
      charged << payload.dig(:payment_method_data, :shared_payment_granted_token)
      Stripe::PaymentIntent.construct_from(id: "pi_#{charged.size}", status: "succeeded", amount: payload[:amount], currency: payload[:currency])
    end
  end

  def top_up(wallet, payment_method)
    create_wallet_transaction({
      wallet_id: wallet.id, paid_credits: "10", invoice_requires_successful_payment: true, payment_method:
    }, as: :model).first
  end

  it "charges each top-up with its own token and nothing else" do
    wallet = create_wallet({external_customer_id: customer.external_id, rate_amount: "1", name: "credits", currency: "USD"}, as: :model)

    top_up(wallet, {payment_method_type: "provider", shared_payment_token: "spt_first"})
    perform_all_enqueued_jobs

    expect(charged).to eq(["spt_first"])
    expect(wallet.reload.credits_balance).to eq(10)

    create_one_off_invoice(customer, [add_on], currency: "USD")
    manual = top_up(wallet, {payment_method_type: "manual"})
    perform_all_enqueued_jobs

    expect(charged).to eq(["spt_first"])
    expect(customer.invoices.where(invoice_type: :one_off).sole.payment_status).to eq("pending")
    expect(manual.reload.invoice.payment_status).to eq("pending")

    top_up(wallet, {payment_method_type: "provider", shared_payment_token: "spt_second"})
    perform_all_enqueued_jobs

    expect(charged).to eq(%w[spt_first spt_second])
    expect(wallet.reload.credits_balance).to eq(20)
    expect(customer.payment_methods.pluck(:provider_method_id, :is_default)).to match_array([["spt_first", false], ["spt_second", false]])
  end
end
