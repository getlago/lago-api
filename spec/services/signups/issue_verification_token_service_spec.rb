# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::IssueVerificationTokenService do
  subject(:result) { described_class.call(pending_signup:) }

  let(:pending_signup) { create(:pending_signup) }

  before { freeze_time }

  it "returns a token whose digest is the attempt's only live link, valid 24 hours" do
    expect(result.token).to match(PendingSignupToken::TOKEN_FORMAT)
    expect(pending_signup.tokens.pending.sole).to have_attributes(
      token_digest: OpenSSL::Digest::SHA256.hexdigest(result.token),
      expires_at: 24.hours.from_now
    )
  end

  context "when issued after the attempt's window" do
    let(:pending_signup) { create(:pending_signup, expires_at: 1.hour.ago) }

    it "still ends the link a day after that window" do
      result

      expect(pending_signup.tokens.pending.sole.expires_at).to eq(1.hour.ago + 24.hours)
    end
  end

  it "replaces only this attempt's previous link" do
    previous = create(:pending_signup_token, pending_signup:)
    other = create(:pending_signup_token, pending_signup: create(:pending_signup, email: pending_signup.email))

    result

    expect(previous.reload).to be_replaced
    expect(other.reload).to be_pending
  end
end
