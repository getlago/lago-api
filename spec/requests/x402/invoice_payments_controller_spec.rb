# frozen_string_literal: true

require "rails_helper"

describe X402::InvoicePaymentsController, :premium do
  include_context "with an x402 payment"

  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:customer) { create(:customer, organization:) }
  let(:token) { "ab" * 32 }
  let(:invoice) do
    create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 105, x402_payment_token: token, x402_connection:)
  end
  let(:payee_address) { "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5" }
  let(:payment_required) { X402::Wire::V2Codec.decode(response.headers["PAYMENT-REQUIRED"]) }
  let(:wallet) { create(:wallet, customer:, currency: "USD", x402_enabled: true) }

  before do
    wallet
    stub_cdp_supported
    invoice
  end

  describe "GET /x402/invoice_payments/:token" do
    subject { get("/x402/invoice_payments/#{token}") }

    it "answers 402" do
      subject

      expect(response).to have_http_status(:payment_required)
    end

    it "challenges for the amount due on the bound connection" do
      subject

      expect(payment_required).to eq(
        "x402Version" => 2,
        "resource" => {"url" => invoice.x402_payment_url, "description" => "Invoice #{invoice.number}", "mimeType" => "application/json"},
        "accepts" => [x402_evm_requirements.merge("amount" => "1050000"), x402_svm_requirements.merge("amount" => "1050000")]
      )
    end

    it "renders the challenge as the body" do
      subject

      expect(JSON.parse(response.body)).to eq(payment_required)
    end

    context "with an unknown token" do
      subject { get("/x402/invoice_payments/#{"cd" * 32}") }

      it "answers 404" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("invoice_not_found")
      end
    end

    context "with a null byte in the token" do
      subject { get("/x402/invoice_payments/ab%00cd") }

      it "answers 404" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("invoice_not_found")
      end
    end

    context "without x402 payments" do
      let(:organization) { create(:organization, feature_flags: []) }

      it "answers 403" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "without premium", premium: false do
      it "answers 403" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "with a paid invoice" do
      let(:invoice) do
        create(
          :invoice,
          organization:, customer:, currency: "USD", total_amount_cents: 105, payment_status: "succeeded",
          x402_payment_token: token, x402_connection:
        )
      end

      it "answers 410 without a challenge" do
        subject

        expect(response).to have_http_status(:gone)
        expect(json).to eq(status: 410, error: "Gone", code: "invalid_invoice_status_or_payment_status")
        expect(response.headers["PAYMENT-REQUIRED"]).to be_nil
      end
    end

    context "with a voided invoice" do
      let(:invoice) do
        create(:invoice, :voided, organization:, customer:, currency: "USD", total_amount_cents: 105, x402_payment_token: token, x402_connection:)
      end

      it "answers 410" do
        subject

        expect(response).to have_http_status(:gone)
      end
    end

    context "with nothing left to pay" do
      let(:invoice) do
        create(
          :invoice,
          organization:, customer:, currency: "USD", total_amount_cents: 105, total_paid_amount_cents: 105,
          x402_payment_token: token, x402_connection:
        )
      end

      it "answers 410" do
        subject

        expect(response).to have_http_status(:gone)
        expect(json[:code]).to eq("invalid_invoice_status_or_payment_status")
      end
    end

    context "with a pending attempt" do
      before { create(:x402_settlement, :pending, :invoice_payment, x402_connection:, invoice:, payee_address:) }

      it "answers 409 without a challenge" do
        subject

        expect(response).to have_http_status(:conflict)
        expect(json).to eq(status: 409, error: "Conflict", code: "invoice_payment_pending")
        expect(response.headers["PAYMENT-REQUIRED"]).to be_nil
      end
    end

    context "with a non-USD invoice" do
      let(:invoice) do
        create(:invoice, organization:, customer:, currency: "EUR", total_amount_cents: 105, x402_payment_token: token, x402_connection:)
      end

      it "answers 422 naming the currency rule" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(base: ["invoice_currency_not_supported"])
      end
    end

    context "without an x402 wallet" do
      let(:wallet) { create(:wallet, customer:, currency: "USD", x402_enabled: false) }

      it "answers 422 naming the wallet rule" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(base: ["wallet_not_x402_enabled"])
      end
    end

    context "with a discarded connection" do
      let(:x402_connection) { create(:x402_connection, :discarded, organization:) }

      it "answers 404 naming the connection" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("connection_not_found")
      end

      it "asks CDP nothing" do
        subject

        expect(a_request(:get, "#{cdp_host}/platform/v2/x402/supported")).not_to have_been_made
      end
    end

    context "with a testnet connection on an organization running on mainnet" do
      let(:organization) { create(:organization, feature_flags: ["x402_payments", "x402_mainnet"]) }
      let(:x402_connection) { create(:x402_connection, :saved_before_switch, organization:) }

      it "answers 422 naming the environment rule" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(connection_code: ["environment_not_enabled"])
        expect(response.headers["PAYMENT-REQUIRED"]).to be_nil
      end
    end

    context "when CDP is unavailable" do
      before { stub_cdp_supported(status: 503) }

      it "answers a third-party error naming the failure" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          status: 422,
          error: "Unprocessable Entity",
          code: "third_party_error",
          error_details: {third_party: "coinbase_cdp", thirdparty_error: "unavailable_error: supported: HTTP 503"}
        )
      end
    end
  end

  describe "POST /x402/invoice_payments/:token" do
    subject { post("/x402/invoice_payments/#{token}") }

    it "challenges like a GET" do
      subject

      expect(response).to have_http_status(:payment_required)
      expect(payment_required["accepts"].size).to eq(2)
    end
  end
end
