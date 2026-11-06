# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::AuthController, :premium, cache: :memory do
  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:base) { "/agents/v1/#{storefront.id}" }
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:public_key) { Base64.urlsafe_encode64(key.raw_public_key, padding: false) }

  def request_challenge(purpose)
    post("#{base}/auth/challenges", params: {public_key:, purpose:}, as: :json)
  end

  def prove(purpose, path)
    request_challenge(purpose)
    signature = Base64.urlsafe_encode64(key.sign(nil, Base64.urlsafe_decode64(json[:message])), padding: false)
    post("#{base}/#{path}", params: {challenge_id: json[:challenge_id], signature:}, as: :json)
  end

  it "signs an agent up, renews its token and revokes it" do
    prove("signup", "signup")
    expect(response).to have_http_status(:ok)
    expect(json).to include(created: true, token_type: "Bearer", expires_in: 300, scope: storefront.scope)
    registration_id = json[:registration_id]
    token = json[:access_token]

    get("#{base}/me", headers: {"Authorization" => "Bearer #{token}"})
    expect(json).to eq(registration_id:, scope: storefront.scope, status: "active")

    prove("authenticate", "auth/token")
    expect(json).to include(registration_id:, created: false)

    prove("revoke", "auth/revoke")
    expect(json).to eq(registration_id:, status: "revoked")

    get("#{base}/me", headers: {"Authorization" => "Bearer #{token}"})
    expect(response).to have_http_status(:unauthorized)
    expect(json[:error]).to eq("registration_inactive")
  end

  it "answers a refused proof with its reason" do
    request_challenge("signup")
    post("#{base}/signup", params: {challenge_id: json[:challenge_id], signature: Base64.urlsafe_encode64("x" * 64, padding: false)}, as: :json)

    expect(response).to have_http_status(:unauthorized)
    expect(json[:error]).to eq("invalid_proof")
  end

  context "when one key asks for more challenges than allowed" do
    before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new }

    it "answers too many requests" do
      11.times { request_challenge("signup") }

      expect(response).to have_http_status(:too_many_requests)
      expect(json[:code]).to eq("too_many_requests")
    end
  end
end
