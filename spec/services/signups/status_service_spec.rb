# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::StatusService do
  subject(:status) { described_class.call(signup_secret:).status }

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let!(:pending_signup) { create(:pending_signup, signup_secret:) }

  before { freeze_time }

  it { is_expected.to eq(:pending) }

  context "when confirmed" do
    let!(:pending_signup) { create(:pending_signup, :verified, signup_secret:) }

    it { is_expected.to eq(:verified) }
  end

  context "when 48 hours have passed since Step 1 without a confirmation" do
    # travel_to drops sub-seconds, so the next second is the first one past the expiry.
    before { travel_to(pending_signup.expires_at + PendingSignupToken::TTL + 1.second) }

    it { is_expected.to eq(:expired) }
  end

  it "answers invalid for an unknown or malformed secret" do
    expect(described_class.call(signup_secret: PendingSignup.generate_signup_secret).status).to eq(:invalid)
    expect(described_class.call(signup_secret: "broken").status).to eq(:invalid)
  end

  context "when the address already had an account" do
    before do
      create(:user, email: pending_signup.email)
      Signups::DeliverVerificationService.call!(pending_signup:)
    end

    it "stays pending, so the secret never reveals the account" do
      expect(status).to eq(:pending)
    end
  end

  context "when another attempt of the same address is confirmed" do
    let(:other_token) { PendingSignupToken.generate }

    before do
      other = create(:pending_signup, email: pending_signup.email)
      create(:pending_signup_token, pending_signup: other, token: other_token)
      Signups::ConfirmService.call!(token: other_token, password: "Lago-Passw0rd")
    end

    it "stays pending and cannot be exchanged" do
      expect(status).to eq(:pending)
      expect(Signups::ExchangeSecretService.call(signup_secret:).error.code).to eq("email_not_verified")
    end
  end
end
