# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::BillingController, :premium, cache: :memory do
  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:base) { "/agents/v1/#{storefront.id}" }
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:public_key) { Base64.urlsafe_encode64(key.raw_public_key, padding: false) }

  before { storefront.update!(plans: [{plan_code: plan.code}]) }

  def token(purpose, path, scope: nil)
    post("#{base}/auth/challenges", params: {public_key:, purpose:, scope:}.compact, as: :json)
    signature = Base64.urlsafe_encode64(key.sign(nil, Base64.urlsafe_decode64(json[:message])), padding: false)
    post("#{base}/#{path}", params: {challenge_id: json[:challenge_id], signature:}, as: :json)
    json[:access_token]
  end

  def mailed_code
    digest = Agents::Claim.sole.verification_code_hash
    CGI.unescapeHTML(ActionMailer::Base.deliveries.last.body.encoded).scan(/\b\d{6}\b/).find { Agents::Claim.digest(it) == digest }
  end

  it "enrolls an agent that holds a billing token" do
    api_token = token("signup", "signup")
    headers = {"Authorization" => "Bearer #{token("authenticate", "auth/token", scope: "billing")}"}

    get("#{base}/billing", headers:)
    expect(json).to include(enrolled: false)

    post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)
    expect(response).to have_http_status(:ok)
    expect(json).to include(enrolled: true, plan_code: plan.code, wallet_code: "agent_credits", currency: "USD", balance_cents: 0)

    get("#{base}/billing", headers:)
    expect(json).to include(enrolled: true, plan_code: plan.code)

    get("#{base}/billing", headers: {"Authorization" => "Bearer #{api_token}"})
    expect(response).to have_http_status(:unauthorized)
    expect(json[:error]).to eq("invalid_token")

    get("#{base}/me", headers:)
    expect(response).to have_http_status(:unauthorized)
    expect(json[:error]).to eq("invalid_token")
  end

  it "answers 429 to a fourth plan change in the hour" do
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    other_plan = create(:plan, organization:, amount_cents: 0, amount_currency: "USD")
    storefront.update!(plans: [{plan_code: plan.code}, {plan_code: other_plan.code}])
    token("signup", "signup")
    headers = {"Authorization" => "Bearer #{token("authenticate", "auth/token", scope: "billing")}"}

    [plan, other_plan, plan, other_plan].each do |next_plan|
      post("#{base}/billing/enroll", params: {plan_code: next_plan.code}, headers:, as: :json)
      expect(response).to have_http_status(:ok)
    end

    post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)
    expect(response).to have_http_status(:too_many_requests)
    expect(json[:code]).to eq("too_many_requests")

    post("#{base}/billing/enroll", params: {plan_code: other_plan.code}, headers:, as: :json)
    expect(response).to have_http_status(:ok)
    expect(json).to include(plan_code: other_plan.code)
  end

  describe "funding" do
    let(:headers) { {"Authorization" => "Bearer #{token("authenticate", "auth/token", scope: "billing")}"} }

    before do
      storefront.update!(plans: [{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}])
      storefront.stripe_provider.update!(seller_profile: "profile_test_123")
      allow(::Stripe::Customer).to receive(:create).and_return(::Stripe::Customer.construct_from(id: "cus_agent"))
      token("signup", "signup")
    end

    it "pays a top-up with a shared payment token and reads it back" do
      post("#{base}/billing/payments", params: {amount_cents: 500, shared_payment_token: "spt_agent_1"}, headers:, as: :json)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error_details]).to eq(base: ["enrollment_required"])

      post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)
      expect(json[:funding]).to eq(seller_profile: "profile_test_123", currency: "USD", minimum_topup_cents: 500, maximum_topup_cents: 10_000)

      post("#{base}/billing/payments", params: {amount_cents: 500, shared_payment_token: "spt_agent_1"}, headers:, as: :json)
      expect(response).to have_http_status(:ok)
      expect(json).to include(status: "pending", amount_cents: 500, currency: "USD", settled_at: nil, failed_at: nil)
      payment_id = json[:id]

      get("#{base}/billing/payments/#{payment_id}", headers:)
      expect(response).to have_http_status(:ok)
      expect(json).to include(id: payment_id, status: "pending", amount_cents: 500)

      post("#{base}/billing/payments", params: {amount_cents: 500, shared_payment_token: "spt_agent_1"}, headers:, as: :json)
      expect(json[:id]).to eq(payment_id)

      post("#{base}/billing/payments", params: {amount_cents: 500, shared_payment_token: 123}, headers:, as: :json)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error_details]).to eq(shared_payment_token: ["value_is_invalid"])
    end

    it "does not show granted credits as a payment" do
      post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)
      granted = create(:wallet_transaction, wallet: Wallet.find_by!(code: json[:wallet_code]), transaction_status: :granted)

      get("#{base}/billing/payments/#{granted.id}", headers:)
      expect(response).to be_not_found_error("payment")
    end

    it "does not show a payment to another agent" do
      post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)
      post("#{base}/billing/payments", params: {amount_cents: 500, shared_payment_token: "spt_agent_1"}, headers:, as: :json)
      payment_id = json[:id]

      other_key = OpenSSL::PKey.generate_key("ED25519")
      other_public_key = Base64.urlsafe_encode64(other_key.raw_public_key, padding: false)
      post("#{base}/auth/challenges", params: {public_key: other_public_key, purpose: "signup"}, as: :json)
      signature = Base64.urlsafe_encode64(other_key.sign(nil, Base64.urlsafe_decode64(json[:message])), padding: false)
      post("#{base}/signup", params: {challenge_id: json[:challenge_id], signature:}, as: :json)
      post("#{base}/auth/challenges", params: {public_key: other_public_key, purpose: "authenticate", scope: "billing"}, as: :json)
      signature = Base64.urlsafe_encode64(other_key.sign(nil, Base64.urlsafe_decode64(json[:message])), padding: false)
      post("#{base}/auth/token", params: {challenge_id: json[:challenge_id], signature:}, as: :json)

      get("#{base}/billing/payments/#{payment_id}", headers: {"Authorization" => "Bearer #{json[:access_token]}"})
      expect(response).to be_not_found_error("payment")
    end
  end

  describe "free credits" do
    let(:headers) { {"Authorization" => "Bearer #{token("authenticate", "auth/token", scope: "billing")}"} }

    before do
      storefront.update!(plans: [{plan_code: plan.code, free_credits_cents: 1000}])
      token("signup", "signup")
    end

    it "grants them once the owner has claimed the agent, and once only" do
      post("#{base}/billing/enroll", params: {plan_code: plan.code}, headers:, as: :json)

      post("#{base}/billing/free_credits", headers:)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error_details]).to eq(base: ["claim_required"])

      post("#{base}/claims/codes", headers:)
      code = json[:claim_code]
      perform_enqueued_jobs do
        post("#{base}/claims/start", params: {claim_code: code, email: "owner@example.com"}, as: :json)
      end
      post("#{base}/claims/verify", params: {claim_code: code, verification_code: mailed_code}, as: :json)
      expect(json).to include(status: "claimed")

      post("#{base}/billing/free_credits", headers:)
      expect(response).to have_http_status(:ok)
      expect(json).to include(status: "granted", amount_cents: 1000)
      transaction_id = json[:wallet_transaction_id]
      expect(transaction_id).to be_present

      get("#{base}/billing", headers:)
      expect(json).to include(balance_cents: 1000)

      post("#{base}/billing/free_credits", headers:)
      expect(response).to have_http_status(:ok)
      expect(json).to eq(status: "granted", amount_cents: 1000, wallet_transaction_id: transaction_id)
    end
  end
end
