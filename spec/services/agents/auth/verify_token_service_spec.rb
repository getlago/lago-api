# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Auth::VerifyTokenService do
  subject(:result) { described_class.call(storefront:, token:) }

  let(:storefront) { create(:agent_storefront_integration) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:claims) { {iss: storefront.agent_url, sub: registration.id, scope: storefront.scope, iat: Time.current.to_i, exp: 5.minutes.from_now.to_i} }
  let(:header) { {typ: "at+jwt"} }
  let(:token) { JWT.encode(claims, RsaPrivateKey, "RS256", header) }

  it "returns the registration" do
    expect(result).to be_success
    expect(result.registration).to eq(registration)
  end

  context "with a token of another connection" do
    let(:claims) { super().merge(iss: create(:agent_storefront_integration, organization: storefront.organization, code: "other_api").agent_url) }

    it "refuses" do
      expect(result.error.message).to eq("invalid_token")
    end
  end

  context "with an expired token" do
    let(:claims) { super().merge(exp: 1.second.ago.to_i) }

    it "refuses" do
      expect(result.error.message).to eq("invalid_token")
    end
  end

  context "with another kind of token signed by the same key" do
    let(:header) { {} }

    it "refuses" do
      expect(result.error.message).to eq("invalid_token")
    end
  end

  context "when the registration is revoked" do
    before { registration.update!(status: :revoked, revoked_at: Time.current) }

    it "refuses" do
      expect(result.error.message).to eq("registration_inactive")
    end
  end
end
