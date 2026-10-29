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

  describe "POST /x402/invoice_payments/:token with a payment" do
    subject { post("/x402/invoice_payments/#{token}", headers: {"PAYMENT-SIGNATURE" => header}) }

    let(:x402_evm_requirements) { super().merge("amount" => "1050000") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "1050000"}}) }
    let(:header) { X402::Wire::V2Codec.encode(x402_evm_payment) }
    let(:payer_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
    let(:receipt) do
      {
        "success" => true,
        "transaction" => "0xefad33f01282b3a8b18893a9eb0aecbc2fc210ffcfa7fda7ca79f14c8822963a",
        "network" => "eip155:84532",
        "payer" => payer_address
      }
    end
    let(:digest) do
      X402::Payments::ComputeDigestService.call(payment: x402_evm_payment, network: "eip155:84532", asset: x402_evm_requirements["asset"]).digest
    end
    let(:payment_response) { X402::Wire::V2Codec.decode(response.headers["PAYMENT-RESPONSE"]) }
    let(:fault) { nil }

    before do
      travel_to(Time.zone.at(1_789_649_271))
      stub_cdp_facilitator(fault:)
    end

    it "answers the receipt" do
      subject

      expect(response).to have_http_status(:ok)
      expect(payment_response).to eq(receipt)
    end

    it "renders the receipt as the body" do
      subject

      expect(JSON.parse(response.body)).to eq(receipt)
    end

    it "marks the invoice paid" do
      subject

      expect(invoice.reload).to have_attributes(payment_status: "succeeded", total_paid_amount_cents: 105)
    end

    it "records one x402 payment" do
      subject

      expect(invoice.payments.sole).to have_attributes(payment_type: "x402", amount_cents: 105)
    end

    context "with a GET" do
      subject { get("/x402/invoice_payments/#{token}", headers: {"PAYMENT-SIGNATURE" => header}) }

      it "answers the receipt" do
        subject

        expect(response).to have_http_status(:ok)
        expect(payment_response).to eq(receipt)
      end
    end

    context "with a resent payment" do
      before { post("/x402/invoice_payments/#{token}", headers: {"PAYMENT-SIGNATURE" => header}) }

      it "answers the same receipt" do
        subject

        expect(payment_response).to eq(receipt)
      end

      it "settles once" do
        subject

        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).to have_been_made.once
      end

      it "records one payment" do
        subject

        expect(invoice.payments.count).to eq(1)
      end
    end

    context "with a resent payment after a void" do
      let(:invoice) do
        create(:invoice, :voided, organization:, customer:, currency: "USD", total_amount_cents: 105, x402_payment_token: token, x402_connection:)
      end

      before do
        create(
          :x402_settlement, :invoice_payment,
          x402_connection:, invoice:, payment_digest: digest, payer_address:, payee_address:, transaction_hash: receipt["transaction"]
        )
      end

      it "answers the receipt" do
        subject

        expect(response).to have_http_status(:ok)
        expect(payment_response).to eq(receipt)
      end

      it "asks CDP nothing" do
        subject

        expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
      end

      context "with another payment" do
        let(:header) { X402::Wire::V2Codec.encode(x402_evm_payment.deep_merge("payload" => {"authorization" => {"nonce" => "0x#{"11" * 32}"}})) }

        it "answers 410" do
          subject

          expect(response).to have_http_status(:gone)
        end
      end
    end

    context "with a payment a paid invoice never received" do
      let(:invoice) do
        create(
          :invoice,
          organization:, customer:, currency: "USD", total_amount_cents: 105, payment_status: "succeeded",
          x402_payment_token: token, x402_connection:
        )
      end

      it "answers 410" do
        subject

        expect(response).to have_http_status(:gone)
      end
    end

    context "when the invoice is marked paid during verification" do
      before do
        allow(X402::Settlements::VerifyService).to receive(:call).and_wrap_original do |original, **kwargs|
          verification = original.call(**kwargs)
          Invoices::UpdateService.call!(invoice: Invoice.find(invoice.id), params: {payment_status: "succeeded"})
          verification
        end
      end

      it "answers 410" do
        subject

        expect(response).to have_http_status(:gone)
        expect(json[:code]).to eq("invalid_invoice_status_or_payment_status")
      end

      it "never settles" do
        subject

        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "with settlement_pending" do
      let(:fault) { :settlement_pending }

      it "answers 409" do
        subject

        expect(response).to have_http_status(:conflict)
        expect(json[:code]).to eq("invoice_payment_pending")
        expect(response.headers["PAYMENT-RESPONSE"]).to be_nil
      end

      it "leaves the invoice unpaid" do
        subject

        expect(invoice.reload.payment_status).to eq("pending")
      end
    end

    context "with a facilitator rejection" do
      let(:fault) { :verify_reject }

      it "answers a fresh challenge naming the reason" do
        subject

        expect(response).to have_http_status(:payment_required)
        expect(payment_required).to include(
          "error" => "invalid_exact_evm_payload_signature",
          "accepts" => [x402_evm_requirements, x402_svm_requirements.merge("amount" => "1050000")]
        )
      end

      it "writes no attempt" do
        expect { subject }.not_to change(X402::Settlement, :count)
      end
    end

    context "when the facilitator is unavailable" do
      before { stub_cdp_answer("/verify", status: 503, body: {errorType: "internal_server_error"}) }

      it "answers a third-party error without the merchant's failure" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(status: 422, error: "Unprocessable Entity", code: "third_party_error")
      end
    end

    context "with a blank payment header" do
      let(:header) { "" }

      it "answers the plain challenge" do
        subject

        expect(response).to have_http_status(:payment_required)
        expect(payment_required).not_to have_key("error")
      end
    end

    context "with a malformed payment header" do
      let(:header) { "%%%" }

      it "answers a fresh challenge naming the payment invalid" do
        subject

        expect(response).to have_http_status(:payment_required)
        expect(payment_required["error"]).to eq("invalid_payment")
      end
    end

    context "with a pending attempt" do
      before { create(:x402_settlement, :pending, :invoice_payment, x402_connection:, invoice:, payee_address:) }

      it "answers 409 without verifying" do
        subject

        expect(response).to have_http_status(:conflict)
        expect(a_request(:post, "#{cdp_facilitator_url}/verify")).not_to have_been_made
      end
    end

    context "with a non-USD invoice" do
      let(:invoice) do
        create(:invoice, organization:, customer:, currency: "EUR", total_amount_cents: 105, x402_payment_token: token, x402_connection:)
      end

      it "answers 422 naming the currency rule without verifying" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(base: ["invoice_currency_not_supported"])
        expect(a_request(:post, "#{cdp_facilitator_url}/verify")).not_to have_been_made
      end
    end

    context "without an x402 wallet" do
      let(:wallet) { create(:wallet, customer:, currency: "USD", x402_enabled: false) }

      it "answers 422 naming the wallet rule without verifying" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(base: ["wallet_not_x402_enabled"])
        expect(a_request(:post, "#{cdp_facilitator_url}/verify")).not_to have_been_made
      end
    end

    context "with a discarded connection" do
      let(:x402_connection) { create(:x402_connection, :discarded, organization:) }

      it "answers 404 naming the connection" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("connection_not_found")
      end
    end
  end
end
