# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Auth::ProofService, cache: :memory do
  subject(:result) { described_class.call(storefront:, challenge_id:, signature:, purpose:) }

  let(:storefront) { create(:agent_storefront_integration) }
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:public_key) { Base64.urlsafe_encode64(key.raw_public_key, padding: false) }
  let(:purpose) { "signup" }
  let(:challenge) { Agents::Auth::ChallengeService.call(storefront: challenge_storefront, public_key:, purpose: challenge_purpose) }
  let(:challenge_storefront) { storefront }
  let(:challenge_purpose) { purpose }
  let(:challenge_id) { challenge.challenge_id }
  let(:signature) { Base64.urlsafe_encode64(key.sign(nil, challenge.message), padding: false) }
  let(:registration) { create(:agent_registration, storefront:, public_key:) }

  before { freeze_time }

  it "creates the registration and issues a token" do
    expect(result).to be_success
    expect(result.created).to be(true)
    expect(result.registration).to have_attributes(
      storefront:,
      organization: storefront.organization,
      key_id: Agents::Auth::ChallengeService.key_id(key.raw_public_key),
      public_key:,
      status: "active",
      last_authenticated_at: Time.current
    )

    claims, header = JWT.decode(result.access_token, RsaPublicKey, true, algorithm: "RS256")
    expect(header).to include("typ" => "at+jwt")
    expect(claims).to include(
      "iss" => storefront.agent_url,
      "sub" => result.registration.id,
      "scope" => storefront.scope,
      "exp" => Time.current.to_i + 300
    )
  end

  it "uses the challenge once" do
    result

    second = described_class.call(storefront:, challenge_id:, signature:, purpose:)
    expect(second.error.message).to eq("invalid_or_expired_challenge")
  end

  context "when the key already has a registration" do
    before { registration }

    it "returns it with a new token" do
      expect(result.created).to be(false)
      expect(result.registration).to eq(registration)
      expect(result.access_token).to be_present
    end

    context "with the authenticate purpose" do
      let(:purpose) { "authenticate" }

      it "renews the token" do
        expect(result.registration).to eq(registration)
        expect(result.registration.last_authenticated_at).to eq(Time.current)
        expect(result.access_token).to be_present
      end
    end

    context "with the revoke purpose" do
      let(:purpose) { "revoke" }

      it "revokes the registration without issuing a token" do
        expect(result.registration).to have_attributes(status: "revoked", revoked_at: Time.current)
        expect(result.access_token).to be_nil
      end
    end

    context "when the registration is revoked" do
      before { registration.update!(status: :revoked, revoked_at: Time.current) }

      it "refuses" do
        expect(result.error.code).to eq("registration_revoked")
      end
    end
  end

  context "with the authenticate purpose and no registration" do
    let(:purpose) { "authenticate" }

    it "refuses" do
      expect(result.error.message).to eq("registration_required")
    end
  end

  context "with a signature that does not verify" do
    let(:signature) { Base64.urlsafe_encode64(OpenSSL::PKey.generate_key("ED25519").sign(nil, challenge.message), padding: false) }

    it "refuses and keeps the challenge for a retry" do
      expect(result.error.message).to eq("invalid_proof")
      expect(Rails.cache.exist?("agents:challenge:#{challenge_id}")).to be(true)
    end
  end

  context "with a malformed signature" do
    let(:signature) { "abc" }

    it "fails" do
      expect(result.error.messages).to eq(signature: ["value_is_invalid"])
    end
  end

  context "with a challenge for another purpose" do
    let(:challenge_purpose) { "revoke" }

    it "refuses" do
      expect(result.error.message).to eq("invalid_or_expired_challenge")
    end
  end

  context "with a challenge of another connection" do
    let(:challenge_storefront) { create(:agent_storefront_integration, organization: storefront.organization, code: "other_api") }

    it "refuses" do
      expect(result.error.message).to eq("invalid_or_expired_challenge")
    end
  end

  context "with an expired challenge" do
    before do
      challenge
      travel(121.seconds)
    end

    it "refuses" do
      expect(result.error.message).to eq("invalid_or_expired_challenge")
    end
  end
end
