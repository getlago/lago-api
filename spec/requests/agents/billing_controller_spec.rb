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
end
