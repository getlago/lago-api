# frozen_string_literal: true

require "rails_helper"

describe X402::Invoices::GenerateChallengeService do
  subject(:result) { described_class.call(invoice:) }

  include_context "with an x402 payment"

  let(:customer) { create(:customer, organization:) }
  let(:invoice) do
    create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 105, x402_payment_token: "ab" * 32, x402_connection:)
  end
  let(:supported_status) { 200 }

  before do
    create(:wallet, customer:, currency: "USD", x402_enabled: true)
    stub_cdp_supported(status: supported_status)
  end

  it "builds a requirement for the amount due on every network of the bound connection" do
    expect(result.requirements).to match(
      [
        include(network: "eip155:84532", amount_atomic: "1050000", pay_to: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5"),
        include(network: "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1", amount_atomic: "1050000", extra: {"feePayer" => "GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb"})
      ]
    )
  end

  context "with a partly paid invoice" do
    let(:invoice) do
      create(
        :invoice,
        organization:, customer:, currency: "USD", total_amount_cents: 105, total_paid_amount_cents: 5,
        x402_payment_token: "ab" * 32, x402_connection:
      )
    end

    it "asks for what is left" do
      expect(result.requirements.first[:amount_atomic]).to eq("1000000")
    end
  end

  context "with a failed payment" do
    let(:invoice) do
      create(
        :invoice,
        organization:, customer:, currency: "USD", total_amount_cents: 105, payment_status: "failed",
        x402_payment_token: "ab" * 32, x402_connection:
      )
    end

    it "builds the requirements" do
      expect(result).to be_success
    end
  end

  context "with a paid invoice" do
    let(:invoice) do
      create(
        :invoice,
        organization:, customer:, currency: "USD", total_amount_cents: 105, payment_status: "succeeded",
        x402_payment_token: "ab" * 32, x402_connection:
      )
    end

    it "refuses it as gone" do
      expect(result.error).to be_a(BaseService::GoneFailure).and have_attributes(code: "invalid_invoice_status_or_payment_status")
    end
  end

  context "with a pending attempt" do
    before do
      create(:x402_settlement, :pending, :invoice_payment, x402_connection:, invoice:, payee_address: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5")
    end

    it "refuses a fresh challenge as a conflict" do
      expect(result.error).to be_a(BaseService::ConflictFailure).and have_attributes(code: "invoice_payment_pending")
    end

    it "asks CDP nothing" do
      result

      expect(a_request(:get, "#{cdp_host}/platform/v2/x402/supported")).not_to have_been_made
    end
  end

  context "with a discarded connection" do
    subject(:result) { described_class.call(invoice: Invoice.find(invoice.id)) }

    let(:x402_connection) { create(:x402_connection, :discarded, organization:) }

    it "names the missing connection" do
      expect(result.error).to be_a(BaseService::NotFoundFailure).and have_attributes(resource: "connection")
    end
  end

  context "with a testnet connection on an organization running on mainnet" do
    let(:organization) { create(:organization, feature_flags: ["x402_mainnet"]) }
    let(:x402_connection) do
      create(:x402_connection, :saved_before_switch, :solana, organization:, cdp_api_key_id:, cdp_api_key_secret:)
    end

    it "refuses the connection" do
      expect(result.error.messages).to eq({connection_code: ["environment_not_enabled"]})
    end

    it "asks CDP nothing" do
      result

      expect(a_request(:get, "#{cdp_host}/platform/v2/x402/supported")).not_to have_been_made
    end
  end

  context "when CDP is unavailable" do
    let(:supported_status) { 503 }

    it "fails as a third-party error" do
      expect(result.error).to be_a(BaseService::ThirdPartyFailure)
    end
  end
end
