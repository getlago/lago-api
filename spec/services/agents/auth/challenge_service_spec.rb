# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Auth::ChallengeService, cache: :memory do
  subject(:result) { described_class.call(storefront:, public_key:, purpose:, scope:) }

  let(:storefront) { create(:agent_storefront_integration) }
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:public_key) { Base64.urlsafe_encode64(key.raw_public_key, padding: false) }
  let(:purpose) { "signup" }
  let(:scope) { nil }

  before { freeze_time }

  it "returns a message bound to the connection, the key, the purpose and the scope, and stores it" do
    expect(result).to be_success
    expect(JSON.parse(result.message)).to match(
      "challenge_id" => result.challenge_id,
      "expires_at" => Time.current.to_i + 120,
      "issued_at" => Time.current.to_i,
      "issuer" => storefront.agent_url,
      "key_fingerprint" => Base64.urlsafe_encode64(Digest::SHA256.digest(key.raw_public_key), padding: false),
      "nonce" => a_string_matching(/\A[A-Za-z0-9_-]{43}\z/),
      "protocol" => "lago-agent-auth-v1",
      "purpose" => "signup",
      "scope" => storefront.scope
    )
    expect(Rails.cache.read("agents:challenge:#{result.challenge_id}"))
      .to include(storefront_id: storefront.id, public_key:, purpose: "signup", scope: storefront.scope, message: result.message)
  end

  context "with the billing scope" do
    let(:purpose) { "authenticate" }
    let(:scope) { "billing" }

    it "puts the scope in the message and the stored challenge" do
      expect(JSON.parse(result.message)["scope"]).to eq("billing")
      expect(Rails.cache.read("agents:challenge:#{result.challenge_id}")).to include(scope: "billing")
    end
  end

  context "with an unknown scope" do
    let(:scope) { "admin" }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(scope: ["value_is_invalid"])
    end
  end

  context "with a public key that is not 32 bytes of unpadded base64url" do
    let(:public_key) { "#{Base64.urlsafe_encode64(key.raw_public_key)}=" }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(public_key: ["value_is_invalid"])
    end
  end

  context "with an unknown purpose" do
    let(:purpose) { "login" }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(purpose: ["value_is_invalid"])
    end
  end
end
