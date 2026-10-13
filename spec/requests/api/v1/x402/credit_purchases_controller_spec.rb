# frozen_string_literal: true

require "rails_helper"

describe Api::V1::X402::CreditPurchasesController, :premium do
  include_context "with an x402 payment"

  describe "POST /api/v1/x402/credit_purchases" do
    subject { post_with_token(organization, "/api/v1/x402/credit_purchases", {credit_purchase: params}) }

    let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
    let(:plan) { create(:plan, organization:, code: "agent_api", amount_cents: 0, amount_currency: "USD") }
    let(:payer_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
    let(:x402_evm_requirements) { super().merge("amount" => "10000000") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "10000000"}}) }
    let(:params) do
      {
        connection_code: x402_connection.code, plan_code: "agent_api", wallet_code: "agent_credits",
        payment: x402_evm_payment, payment_requirements: x402_evm_requirements,
        wallet: {name: "Agent credits", rate_amount: "0.001", currency: "USD"}
      }
    end
    let(:fault) { nil }

    before do
      travel_to(Time.zone.at(1_789_649_271))
      stub_cdp_facilitator(fault:)
      plan
    end

    include_examples "requires API permission", "x402", "write"

    context "with a first purchase" do
      it "renders the settled purchase" do
        subject
        expect(json[:x402_settlement]).to include(
          status: "settled", replayed: false, network: "eip155:84532",
          transaction_hash: "0xefad33f01282b3a8b18893a9eb0aecbc2fc210ffcfa7fda7ca79f14c8822963a",
          payer_address:, external_subscription_id: "x402_#{payer_address}_agent_api",
          credits_granted: "10000.0", settled_amount_cents: 1000, reconcile_after: nil
        )
      end
    end

    context "with a resent payment" do
      before { post_with_token(organization, "/api/v1/x402/credit_purchases", {credit_purchase: params}) }

      it "renders the replay" do
        subject
        expect(json[:x402_settlement]).to include(status: "settled", replayed: true, external_subscription_id: "x402_#{payer_address}_agent_api")
      end
    end

    context "with settlement_pending" do
      let(:fault) { :settlement_pending }

      it "renders the pending purchase" do
        subject
        expect(json[:x402_settlement]).to include(
          status: "pending", replayed: false, transaction_hash: nil, credits_granted: nil,
          external_subscription_id: nil, reconcile_after: Time.zone.at(1_789_649_361).iso8601
        )
      end
    end

    context "with the bazaar extension" do
      let(:x402_evm_payment) do
        super().merge(
          "extensions" => {
            "bazaar" => {
              "info" => {"input" => {"type" => "http", "method" => "POST"}, "output" => {"example" => [nil, [1, 2], {"next" => nil}]}},
              "schema" => {"type" => "object", "required" => ["input"]}
            }
          }
        )
      end

      it "forwards the payment unchanged" do
        subject
        expect(a_request(:post, "#{cdp_facilitator_url}/verify").with { |request| JSON.parse(request.body)["paymentPayload"] == x402_evm_payment }).to have_been_made.once
      end
    end

    context "with the root key only in the query string" do
      subject { post_with_token(organization, "/api/v1/x402/credit_purchases?credit_purchase[connection_code]=#{x402_connection.code}", {}) }

      it "answers 422 without a payment" do
        subject
        expect(json[:error_details]).to eq(payment: ["invalid_payment"])
      end
    end

    context "with a form-encoded body" do
      subject do
        post(
          "/api/v1/x402/credit_purchases",
          params: {credit_purchase: {connection_code: x402_connection.code}},
          headers: {"Authorization" => "Bearer #{organization.api_keys.first.value}"}
        )
      end

      it "answers 422 without a payment" do
        subject
        expect(json[:error_details]).to eq(payment: ["invalid_payment"])
      end
    end

    context "with a scalar root" do
      let(:params) { "x" }

      it "answers 400" do
        subject
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with an unknown connection" do
      let(:params) { super().merge(connection_code: "unknown") }

      it "answers not found" do
        subject
        expect(response).to be_not_found_error("connection")
      end
    end

    context "with a wallet shape outside USD" do
      let(:params) { super().merge(wallet: {name: "Agent credits", rate_amount: "0.001", currency: "EUR"}) }

      it "answers 422 with the code" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(wallet: ["currency_not_supported"])
      end
    end

    context "with a grant failing after the settle" do
      before { allow(X402::Subscriptions::ResolveService).to receive(:call!).and_raise(ActiveRecord::LockWaitTimeout) }

      it "answers 422 with the code" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(base: ["credit_grant_failed"])
      end
    end

    context "with a facilitator outage on /verify" do
      before { stub_cdp_answer("/verify", status: 500, body: {errorType: "internal_server_error", correlationId: "corr-1"}) }

      it "answers a third-party error" do
        subject
        expect(json).to include(code: "third_party_error", error_details: {third_party: "coinbase_cdp", thirdparty_error: a_string_including("unavailable_error")})
      end
    end
  end
end
