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
end
