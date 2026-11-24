# frozen_string_literal: true

require "rails_helper"

describe "Payment URL of a paid wallet top-up" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, currency: "USD") }
  let(:payment_url) { "https://checkout.stripe.com/c/pay/cs_test_topup" }
  let(:invoice_requires_successful_payment) { false }

  before do
    setup_stripe_for(customer:)

    stripe_customer = customer.stripe_customer
    stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}")
      .and_return(status: 200, body: get_stripe_fixtures("customer_retrieve_response.json"))
    stub_request(:get, %r{\Ahttps://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}/payment_methods/})
      .and_return(status: 200, body: get_stripe_fixtures("retrieve_payment_method_response.json"))
    # The automatic payment stays in progress, so the invoice remains unpaid
    allow(::Stripe::PaymentIntent).to receive(:create) do |payload, _opts|
      ::Stripe::PaymentIntent.construct_from(id: "pi_1", status: "processing", amount: payload[:amount], currency: payload[:currency])
    end
    allow(::Stripe::Checkout::Session).to receive(:create).and_return({"id" => "cs_test_topup", "url" => payment_url})
  end

  def top_up_and_request_payment_url
    wallet = create_wallet({
      external_customer_id: customer.external_id,
      rate_amount: "1",
      name: "Wallet",
      currency: "USD"
    }, as: :model)

    wallet_transaction = create_wallet_transaction({
      wallet_id: wallet.id,
      paid_credits: "200",
      invoice_requires_successful_payment:
    }, as: :model).first

    post_with_token(organization, "/api/v1/wallet_transactions/#{wallet_transaction.id}/payment_url")
  end

  shared_examples "a payment URL for the full top-up amount" do
    it "builds the Stripe Checkout from the invoice totals" do
      top_up_and_request_payment_url

      invoice = customer.invoices.credit.sole
      expect(invoice.status).to eq(expected_status)
      expect(invoice.payment_status).to eq("pending")
      expect(invoice.total_due_amount_cents).to eq(20_000) # 200 credits x rate 1 x 100 cents

      expect(response).to have_http_status(:success)
      expect(json[:wallet_transaction_payment_details][:payment_url]).to eq(payment_url)
      expect(::Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          line_items: [
            hash_including(
              price_data: hash_including(
                currency: "usd",
                unit_amount: 20_000, # 200 credits x rate 1 x 100 cents
                product_data: {name: invoice.number}
              )
            )
          ]
        ),
        anything
      )
    end
  end

  context "when the invoice is finalized" do
    let(:expected_status) { "finalized" }

    it_behaves_like "a payment URL for the full top-up amount"
  end

  context "when the invoice waits for a successful payment", :premium do
    let(:invoice_requires_successful_payment) { true }
    let(:expected_status) { "open" }

    it_behaves_like "a payment URL for the full top-up amount"
  end
end
