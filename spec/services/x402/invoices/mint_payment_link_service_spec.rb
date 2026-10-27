# frozen_string_literal: true

require "rails_helper"

describe X402::Invoices::MintPaymentLinkService, :premium do
  subject(:result) { described_class.call(invoice:, connection_code:) }

  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:customer) { create(:customer, organization:) }
  let(:connection) { create(:x402_connection, organization:) }
  let(:connection_code) { connection.code }
  let(:invoice) { create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000) }

  before { create(:wallet, customer:, currency: "USD", x402_enabled: true) }

  it "binds a new token to the connection" do
    expect(result).to be_success
    expect(invoice.reload).to have_attributes(x402_connection_id: connection.id, x402_payment_token: match(/\A\h{64}\z/))
  end

  it "returns the invoice" do
    expect(result.invoice).to eq(invoice)
  end

  context "when the invoice is bound to the connection" do
    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000,
        x402_connection: connection, x402_payment_token: "ab" * 32)
    end

    it "keeps the token" do
      expect { result }.not_to change { invoice.reload.x402_payment_token }
    end
  end

  context "when the invoice is bound to another connection" do
    let(:other_connection) { create(:x402_connection, organization:) }
    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000,
        x402_connection: other_connection, x402_payment_token: "ab" * 32)
    end

    it "mints a new token" do
      expect { result }.to change { invoice.reload.x402_payment_token }.from("ab" * 32).to(match(/\A\h{64}\z/))
    end

    it "rebinds the invoice" do
      expect { result }.to change { invoice.reload.x402_connection_id }.from(other_connection.id).to(connection.id)
    end
  end

  context "when the invoice is bound to a discarded connection" do
    let(:discarded_connection) { create(:x402_connection, :discarded, organization:) }
    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000,
        x402_connection: discarded_connection, x402_payment_token: "ab" * 32)
    end

    it "rebinds the invoice" do
      expect { result }.to change { invoice.reload.x402_connection_id }.from(discarded_connection.id).to(connection.id)
    end
  end

  context "when the organization moved to mainnet" do
    let(:organization) { create(:organization, feature_flags: ["x402_payments", "x402_mainnet"]) }
    let(:testnet_connection) { create(:x402_connection, :saved_before_switch, organization:) }
    let(:connection) { create(:x402_connection, :mainnet, organization:) }
    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000,
        x402_connection: testnet_connection, x402_payment_token: "ab" * 32)
    end

    it "rebinds the invoice to the mainnet connection" do
      expect { result }.to change { invoice.reload.x402_connection_id }.from(testnet_connection.id).to(connection.id)
    end

    it "mints a new token" do
      expect { result }.to change { invoice.reload.x402_payment_token }.from("ab" * 32).to(match(/\A\h{64}\z/))
    end

    context "with the testnet connection code" do
      let(:connection_code) { testnet_connection.code }
      let(:invoice) do
        create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000,
          x402_connection: connection, x402_payment_token: "ab" * 32)
      end

      it "fails on connection_code" do
        expect(result.error.messages).to eq(connection_code: ["environment_not_enabled"])
      end

      it "keeps the binding" do
        expect { result }.not_to change { invoice.reload.slice(:x402_connection_id, :x402_payment_token) }
      end
    end
  end

  context "when the organization moved back to testnet" do
    let(:mainnet_connection) { create(:x402_connection, :mainnet, :saved_before_switch, organization:) }
    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000,
        x402_connection: mainnet_connection, x402_payment_token: "ab" * 32)
    end

    it "fails on connection_code" do
      expect(result.error.messages).to eq(connection_code: ["invoice_bound_to_mainnet"])
    end

    it "keeps the binding" do
      expect { result }.not_to change { invoice.reload.slice(:x402_connection_id, :x402_payment_token) }
    end

    context "with the mainnet connection deleted" do
      let(:mainnet_connection) { create(:x402_connection, :mainnet, :saved_before_switch, :discarded, organization:) }

      it "fails on connection_code" do
        expect(result.error.messages).to eq(connection_code: ["invoice_bound_to_mainnet"])
      end
    end
  end

  context "without x402 payments" do
    let(:organization) { create(:organization) }
    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000,
        x402_connection: connection, x402_payment_token: "ab" * 32)
    end

    it "fails with a forbidden error" do
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("feature_unavailable")
    end
  end

  context "without a connection code" do
    let(:connection_code) { nil }

    it "fails on connection_code" do
      expect(result.error.messages).to eq(connection_code: ["value_is_mandatory"])
    end
  end

  context "with a blank connection code" do
    let(:connection_code) { "" }

    it "fails on connection_code" do
      expect(result.error.messages).to eq(connection_code: ["value_is_mandatory"])
    end
  end

  context "with an unknown connection code" do
    let(:connection_code) { "unknown" }

    it "fails with connection_not_found" do
      expect(result.error.error_code).to eq("connection_not_found")
    end
  end

  context "with a discarded connection" do
    let(:connection) { create(:x402_connection, :discarded, organization:) }

    it "fails with connection_not_found" do
      expect(result.error.error_code).to eq("connection_not_found")
    end
  end

  context "with a connection of another organization" do
    let(:connection) { create(:x402_connection, organization: create(:organization)) }

    it "fails with connection_not_found" do
      expect(result.error.error_code).to eq("connection_not_found")
    end

    it "mints nothing" do
      expect { result }.not_to change { invoice.reload.x402_payment_token }.from(nil)
    end
  end

  context "with a non-USD invoice" do
    let(:invoice) { create(:invoice, organization:, customer:, currency: "EUR", total_amount_cents: 1_000) }

    it "fails with the refusal" do
      expect(result.error.messages).to eq(base: ["invoice_currency_not_supported"])
    end

    it "mints nothing" do
      expect { result }.not_to change { invoice.reload.x402_payment_token }.from(nil)
    end
  end

  context "with a pending x402 attempt" do
    let(:other_connection) { create(:x402_connection, organization:) }
    let(:connection_code) { other_connection.code }
    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1_000,
        x402_connection: connection, x402_payment_token: "ab" * 32)
    end

    before { create(:x402_settlement, :invoice_payment, :pending, x402_connection: connection, invoice:) }

    it "fails with invoice_payment_pending" do
      expect(result.error.messages).to eq(base: ["invoice_payment_pending"])
    end

    it "keeps the binding" do
      expect { result }.not_to change { invoice.reload.x402_connection_id }.from(connection.id)
    end
  end

  context "with a failed x402 attempt" do
    before { create(:x402_settlement, :invoice_payment, :failed, x402_connection: connection, invoice:) }

    it { expect(result).to be_success }
  end

  context "when the invoice was voided after it was loaded" do
    subject(:result) { described_class.call(invoice: loaded_invoice, connection_code:) }

    let(:invoice) { create(:invoice, :voided, organization:, customer:, currency: "USD", total_amount_cents: 1_000) }
    let(:loaded_invoice) do
      Invoice.find(invoice.id).tap do |loaded|
        loaded.status = "finalized"
        loaded.clear_changes_information
      end
    end

    it "fails with invalid_invoice_status_or_payment_status" do
      expect(result.error.messages).to eq(base: ["invalid_invoice_status_or_payment_status"])
    end

    it "mints nothing" do
      expect { result }.not_to change { invoice.reload.x402_payment_token }.from(nil)
    end
  end
end
