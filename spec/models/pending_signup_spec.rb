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

    it "composes after downcasing, as the mailbox key does" do
      expect(described_class.normalize_email("Joa\u0303o@GetLago.com")).to eq("jo\u00E3o@getlago.com")
      expect(described_class.normalize_email("J\u030Cohn@getlago.com")).to eq("\u01F0ohn@getlago.com")
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

  describe "#signup_secret_matches?" do
    let(:signup_secret) { described_class.generate_signup_secret }
    let(:record) { create(:pending_signup, signup_secret:) }

    it "matches only the attempt's own secret" do
      expect(record.signup_secret_matches?(signup_secret)).to be(true)
      expect(record.signup_secret_matches?(described_class.generate_signup_secret)).to be(false)
      expect(record.signup_secret_matches?(nil)).to be(false)
      expect(record.signup_secret_matches?("not-a-secret")).to be(false)
    end
  end

  describe "#email_registered?" do
    let(:record) { create(:pending_signup, email: "jane@getlago.com") }

    it "is true once a user exists for the address, whatever its case" do
      expect(record.email_registered?).to be(false)

      create(:user, email: "Jane@GetLago.com")

      expect(record.email_registered?).to be(true)
    end
  end

  describe ".mailbox_send_state" do
    subject(:state) { described_class.mailbox_send_state("jane@acme.com", now) }

    let(:now) { Time.current }

    before { freeze_time }

    it "has no refusal and no wait without sends" do
      expect(state).to eq([nil, 0])
    end

    context "with a send 59 seconds ago" do
      before { create(:pending_signup, email: "jane@acme.com", emails_sent_at: [59.seconds.ago]) }

      it { is_expected.to eq([:too_soon, 1]) }
    end

    context "with a send exactly 60 seconds ago" do
      before { create(:pending_signup, email: "jane@acme.com", emails_sent_at: [60.seconds.ago]) }

      it { is_expected.to eq([nil, 0]) }
    end

    context "with 3 sends in the hour, across attempts of +tags of the mailbox" do
      before do
        create(:pending_signup, email: "jane@acme.com", emails_sent_at: [50.minutes.ago, 40.minutes.ago])
        create(:pending_signup, email: "jane+1@acme.com", emails_sent_at: [30.minutes.ago])
      end

      # the oldest send, 50 minutes ago, leaves the hour in 10 minutes
      it { is_expected.to eq([:limit_reached, 10 * 60]) }

      context "when the oldest send is exactly one hour old" do
        before { travel 10.minutes }

        it { is_expected.to eq([nil, 0]) }
      end
    end

    context "with 3 sends, the last one within 60 seconds" do
      before { create(:pending_signup, email: "jane@acme.com", emails_sent_at: [20.minutes.ago, 10.minutes.ago, 10.seconds.ago]) }

      # the limit comes first; the oldest send, 20 minutes ago, leaves the hour in 40 minutes
      it { is_expected.to eq([:limit_reached, 40 * 60]) }
    end

    context "with sends of an attempt created more than 25 hours ago" do
      before { create(:pending_signup, email: "jane@acme.com", created_at: 26.hours.ago, emails_sent_at: [10.seconds.ago]) }

      it { is_expected.to eq([nil, 0]) }
    end

    context "with a send to the mailbox" do
      before { create(:pending_signup, email: "jane@acme.com", emails_sent_at: [20.seconds.ago]) }

      it "reads the sends once" do
        queries = 0
        counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { state }

        expect(queries).to eq(1)
      end
    end
  end

  describe "#resend_available_in_seconds and #resend_limit_reached?" do
    subject(:countdown) { [record.resend_available_in_seconds(Time.current), record.resend_limit_reached?] }

    let(:emails_sent_at) { [20.seconds.ago] }
    let(:expires_at) { 22.hours.from_now }
    let(:record) { create(:pending_signup, email: "jane@getlago.com", emails_sent_at:, expires_at:) }

    before { freeze_time }

    it "counts down from the attempt's last send" do
      expect(countdown).to eq([40, false])
    end

    context "without an email of the attempt recorded yet" do
      let(:emails_sent_at) { [] }

      it { is_expected.to eq([0, false]) }
    end

    context "with other emails to its mailbox" do
      let(:emails_sent_at) { [30.minutes.ago] }

      before { create(:pending_signup, email: "jane+a@getlago.com", emails_sent_at: [50.minutes.ago, 40.minutes.ago]) }

      # 3 emails to the mailbox in the hour: the oldest, sent 50 minutes ago, leaves it in 10 minutes
      it { is_expected.to eq([10 * 60, false]) }

      context "when the wait would end with the attempt's window" do
        let(:expires_at) { 10.minutes.from_now }

        it { is_expected.to eq([nil, false]) }
      end
    end

    context "with the attempt's 3 emails sent" do
      let(:record) { build(:pending_signup, :exhausted) }

      it { is_expected.to eq([nil, true]) }
    end

    context "with an expired attempt" do
      let(:record) { build(:pending_signup, expires_at: Time.current) }

      it { is_expected.to eq([nil, false]) }
    end
  end

  describe "#wait_ends_in_window?" do
    subject(:in_window) { pending_signup.wait_ends_in_window?(Time.current, wait) }

    let(:pending_signup) { build(:pending_signup, expires_at: 10.minutes.from_now) }

    before { freeze_time }

    context "with a wait ending before the expiry" do
      let(:wait) { 10.minutes.to_i - 1 }

      it { is_expected.to be(true) }
    end

    context "with a wait ending at the expiry" do
      let(:wait) { 10.minutes.to_i }

      it { is_expected.to be(false) }
    end
  end

  describe "#sending_open?" do
    subject(:open) { record.sending_open?(Time.current) }

    let(:record) { build(:pending_signup) }

    before { freeze_time }

    it { is_expected.to be(true) }

    context "with the attempt's 3 emails sent" do
      let(:record) { build(:pending_signup, :exhausted) }

      it { is_expected.to be(false) }
    end

    context "when the attempt has expired" do
      let(:record) { build(:pending_signup, expires_at: Time.current) }

      it { is_expected.to be(false) }
    end
  end
end
