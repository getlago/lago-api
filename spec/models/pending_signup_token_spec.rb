# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingSignupToken do
  subject(:pending_signup_token) { build(:pending_signup_token) }

  describe "enums" do
    it do
      expect(pending_signup_token).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(pending: "pending", consumed: "consumed", replaced: "replaced")
    end
  end

  describe "associations" do
    it do
      expect(pending_signup_token).to belong_to(:pending_signup)
    end
  end

  describe "validations" do
    it do
      expect(pending_signup_token).to validate_presence_of(:token_digest)
      expect(pending_signup_token).to validate_presence_of(:expires_at)
    end
  end

  describe ".for_token" do
    let(:token) { described_class.generate }
    let!(:record) { create(:pending_signup_token, token:) }

    it "finds the link by the digest of its token" do
      expect(described_class.for_token(token)).to eq(record)
      expect(record.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(token))
    end

    it "returns nil for a malformed or unknown token" do
      expect(described_class.for_token(token[0..41])).to be_nil
      expect(described_class.for_token("#{token[0..41]}=")).to be_nil
      expect(described_class.for_token(described_class.generate)).to be_nil
    end
  end

  describe "#expired?" do
    it "is expired from expires_at on" do
      freeze_time
      record = build(:pending_signup_token, expires_at: Time.current)

      expect(record.expired?(1.second.ago)).to be(false)
      expect(record.expired?(Time.current)).to be(true)
    end
  end

  describe "one live link per attempt" do
    let(:pending_signup) { create(:pending_signup) }

    before { create(:pending_signup_token, pending_signup:) }

    it "refuses a second pending link on one attempt" do
      expect { create(:pending_signup_token, pending_signup:) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "accepts pending links on two attempts of one address" do
      other = create(:pending_signup, email: pending_signup.email)

      expect { create(:pending_signup_token, pending_signup: other) }.not_to raise_error
    end
  end
end
