# frozen_string_literal: true

require "rails_helper"

describe "Wallet Transaction with rounding", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  around { |test| lago_premium!(&test) }

  it "rounds the amount field correctly" do
    create_wallet({
      external_customer_id: customer.external_id,
      rate_amount: "0.001",
      name: "Wallet1",
      currency: "EUR",
      invoice_requires_successful_payment: false
    })
    wallet = customer.wallets.sole

    expect(wallet.rate_amount).to eq(0.001)
  end
end
