# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingSignup do
  subject(:pending_signup) { build(:pending_signup) }

  describe "associations" do
    it do
      expect(pending_signup).to belong_to(:user).optional
      expect(pending_signup).to have_many(:tokens).class_name("PendingSignupToken").inverse_of(:pending_signup)
    end
  end

  describe "validations" do
    it do
      expect(pending_signup).to validate_presence_of(:email)
      expect(pending_signup).to validate_presence_of(:normalized_email)
      expect(pending_signup).to validate_presence_of(:mailbox_key)
      expect(pending_signup).to validate_presence_of(:signup_secret_digest)
      expect(pending_signup).to validate_presence_of(:expires_at)
      expect(pending_signup).to validate_presence_of(:password_digest).on(:create)
    end
  end

  describe ".normalize_email" do
    it "sanitizes and downcases like the user lookups" do
      expect(described_class.normalize_email(" Jane​@GetLago.com ")).to eq("jane@getlago.com")
    end
  end

  describe ".mailbox_key" do
    it "drops the +tag and composes the local part" do
      expect(described_class.mailbox_key("Jane+X@Acme.com")).to eq("jane@acme.com")
      expect(described_class.mailbox_key("+x@acme.com")).to eq("+x@acme.com")
      expect(described_class.mailbox_key("joão@acme.com")).to eq(described_class.mailbox_key("joão@acme.com"))
    end
  end

  describe ".digest_password" do
    it "is accepted by authenticate" do
      record = build(:pending_signup, password_digest: described_class.digest_password("Lago-Passw0rd"))

      expect(record.authenticate("Lago-Passw0rd")).to eq(record)
      expect(record.authenticate("lago-passw0rd")).to be(false)
    end
  end

  describe ".for_signup_secret" do
    let(:signup_secret) { described_class.generate_signup_secret }
    let!(:record) { create(:pending_signup, signup_secret:) }

    it "finds the attempt by the digest of its secret" do
      expect(described_class.for_signup_secret(signup_secret)).to eq(record)
      expect(record.signup_secret_digest).not_to eq(signup_secret)
    end

    it "returns nil for a malformed or unknown secret" do
      expect(described_class.for_signup_secret("short")).to be_nil
      expect(described_class.for_signup_secret("#{signup_secret[0..41]}!")).to be_nil
      expect(described_class.for_signup_secret(described_class.generate_signup_secret)).to be_nil
      expect(described_class.for_signup_secret(nil)).to be_nil
    end
  end

  describe ".mailbox_send_refusal" do
    subject(:refusal) { described_class.mailbox_send_refusal("jane@acme.com", Time.current) }

    before { freeze_time }

    it "is nil without sends" do
      expect(refusal).to be_nil
    end

    context "with a send 59 seconds ago" do
      before { create(:pending_signup, email: "jane@acme.com", emails_sent_at: [59.seconds.ago]) }

      it { is_expected.to eq(:too_soon) }
    end

    context "with a send exactly 60 seconds ago" do
      before { create(:pending_signup, email: "jane@acme.com", emails_sent_at: [60.seconds.ago]) }

      it { is_expected.to be_nil }
    end

    context "with 3 sends in the hour, across attempts of +tags of the mailbox" do
      before do
        create(:pending_signup, email: "jane@acme.com", emails_sent_at: [50.minutes.ago, 40.minutes.ago])
        create(:pending_signup, email: "jane+1@acme.com", emails_sent_at: [30.minutes.ago])
      end

      it { is_expected.to eq(:limit_reached) }

      context "when the oldest send is exactly one hour old" do
        before { travel 10.minutes }

        it { is_expected.to be_nil }
      end
    end

    context "with 3 sends, the last one within 60 seconds" do
      before { create(:pending_signup, email: "jane@acme.com", emails_sent_at: [20.minutes.ago, 10.minutes.ago, 10.seconds.ago]) }

      it "reports the limit first" do
        expect(refusal).to eq(:limit_reached)
      end
    end

    context "with sends of an attempt created more than 25 hours ago" do
      before { create(:pending_signup, email: "jane@acme.com", created_at: 26.hours.ago, emails_sent_at: [10.seconds.ago]) }

      it { is_expected.to be_nil }
    end
  end

  describe "#sending_open?" do
    it "closes after 3 emails or at the expiry" do
      freeze_time

      expect(build(:pending_signup).sending_open?(Time.current)).to be(true)
      expect(build(:pending_signup, :exhausted).sending_open?(Time.current)).to be(false)
      expect(build(:pending_signup, expires_at: Time.current).sending_open?(Time.current)).to be(false)
    end
  end
end
