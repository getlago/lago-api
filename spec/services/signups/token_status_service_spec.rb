# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::TokenStatusService do
  subject(:result) { described_class.call(token:, signup_secret:) }

  let(:signup_secret) { nil }
  let(:attempt_secret) { PendingSignup.generate_signup_secret }
  let(:pending_signup) { create(:pending_signup, email: "Jane@GetLago.com", signup_secret: attempt_secret) }
  let(:token) { PendingSignupToken.generate }
  let!(:token_record) { create(:pending_signup_token, pending_signup:, token:) }

  it "returns the state and the email of a valid link, and asks for the password without the secret" do
    expect(result.status).to eq(:valid)
    expect(result.email).to eq("Jane@GetLago.com")
    expect(result.password_required).to be(true)
  end

  context "with the secret of the attempt that sent the link" do
    let(:signup_secret) { attempt_secret }

    it "does not ask for the password" do
      expect(result.password_required).to be(false)
    end
  end

  context "with the secret of another attempt of the same address" do
    let(:signup_secret) { PendingSignup.generate_signup_secret }

    before { create(:pending_signup, email: "jane@getlago.com", signup_secret:) }

    it "asks for the password" do
      expect(result.password_required).to be(true)
    end
  end

  it "returns no email for a link that is not valid" do
    {
      expired: {expires_at: 1.second.ago},
      locked: {failed_password_attempts: 5},
      replaced: {status: "replaced"},
      already_verified: {status: "consumed", consumed_at: Time.current}
    }.each do |status, attributes|
      token_record.update!(status: "pending", consumed_at: nil, expires_at: 1.day.from_now, failed_password_attempts: 0)
      token_record.update!(attributes)

      answer = described_class.call(token:)

      expect([answer.status, answer.email]).to eq([status, nil])
    end
  end

  it "answers invalid for a malformed or unknown token" do
    expect(described_class.call(token: "broken").status).to eq(:invalid)
    expect(described_class.call(token: PendingSignupToken.generate).status).to eq(:invalid)
  end

  it "writes nothing, so a mail scanner opening the link changes nothing" do
    expect { 2.times { described_class.call(token:) } }.not_to change { [token_record.reload.updated_at, pending_signup.reload.updated_at] }
  end
end
