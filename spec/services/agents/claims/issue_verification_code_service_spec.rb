# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Claims::IssueVerificationCodeService do
  subject(:result) { described_class.call(claim:) }

  let(:claim) { create(:agent_claim, :started) }

  it "stores the digest of a six-digit code with its expiry and returns the code" do
    freeze_time do
      expect(result).to be_success
      expect(result.code).to match(/\A\d{6}\z/)
      expect(claim.reload).to have_attributes(
        verification_code_hash: Agents::Claim.digest(result.code),
        verification_expires_at: 10.minutes.from_now
      )
    end
  end

  it "replaces the previous code" do
    first = described_class.call(claim:).code

    expect(result).to be_success
    expect(claim.reload.verification_code_hash).to eq(Agents::Claim.digest(result.code))
    expect(Agents::Claim.digest(first)).not_to eq(claim.verification_code_hash) if first != result.code
  end
end
