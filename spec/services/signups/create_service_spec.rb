# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::CreateService do
  subject(:result) { described_class.call(email:, password:) }

  let(:email) { "Jane@GetLago.com" }
  # Not the factories' password, so the BCrypt spy only sees the Step 1 hash.
  let(:password) { "Signup-Passw0rd" }

  before { allow(BCrypt::Password).to receive(:create).and_call_original }

  context "with a company email and a valid password" do
    before { freeze_time }

    it "stores one attempt with digests only and returns its secret" do
      expect { result }.to change(PendingSignup, :count).by(1)

      pending_signup = PendingSignup.sole
      expect(result.signup_secret).to match(PendingSignup::SECRET_FORMAT)
      expect(pending_signup).to have_attributes(
        email: "Jane@GetLago.com",
        normalized_email: "jane@getlago.com",
        mailbox_key: "jane@getlago.com",
        signup_secret_digest: PendingSignup.digest_signup_secret(result.signup_secret),
        expires_at: 24.hours.from_now,
        emails_sent_at: [Time.current]
      )
      expect(pending_signup.password_digest).not_to include(password)
      expect(pending_signup.authenticate(password)).to eq(pending_signup)
    end

    it "enqueues the delivery with the attempt id only" do
      expect { result }.to have_enqueued_job_after_commit(Signups::DeliverVerificationJob).with(kind_of(String))
      expect(Signups::DeliverVerificationJob).to have_been_enqueued.with(PendingSignup.sole.id)
    end

    it "creates no user, organization or membership" do
      expect { result }.not_to change { [User.count, Organization.count, Membership.count] }
    end
  end

  context "when the address already has a user, whatever its case" do
    before { create(:user, email: "jane@getlago.com") }

    it "answers and works exactly as for a new address" do
      expect(result).to be_success
      expect(result.signup_secret).to match(PendingSignup::SECRET_FORMAT)
      expect(PendingSignup.count).to eq(1)
      expect(BCrypt::Password).to have_received(:create).with(password, anything).once
      expect(Signups::DeliverVerificationJob).to have_been_enqueued.with(PendingSignup.sole.id)
    end
  end

  context "with an address the email policy refuses" do
    it "refuses personal, throwaway, literal and quoted addresses with the policy's codes" do
      codes = ["jane@gmail.com", "x@abc.mailinator.com", "jane@[10.0.0.1]", "\"jane\"@getlago.com"].index_with do
        described_class.call(email: it, password:).error.messages[:email]
      end

      expect(codes).to eq(
        "jane@gmail.com" => ["email_domain_not_allowed"],
        "x@abc.mailinator.com" => ["email_domain_not_allowed"],
        "jane@[10.0.0.1]" => ["email_domain_not_allowed"],
        "\"jane\"@getlago.com" => ["invalid_email_format"]
      )
      expect(PendingSignup.count).to eq(0)
      expect(Signups::DeliverVerificationJob).not_to have_been_enqueued
      expect(BCrypt::Password).not_to have_received(:create).with(password, anything)
    end
  end

  context "with a blank email and a weak password" do
    let(:email) { "" }
    let(:password) { "lago" }

    it "returns both errors together without hashing or storing anything" do
      expect(result.error.messages).to eq(
        email: ["value_is_mandatory"],
        password: %w[password_too_short password_missing_uppercase password_missing_number password_missing_special_character]
      )
      expect(PendingSignup.count).to eq(0)
      expect(BCrypt::Password).not_to have_received(:create).with(password, anything)
    end
  end

  context "with a blank password" do
    let(:password) { "" }

    it "answers value_is_mandatory" do
      expect(result.error.messages).to eq(password: ["value_is_mandatory"])
    end
  end

  describe "per-mailbox limits" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { Auth::AttemptsThrottle.store = cache }

    it "refuses a second email to the mailbox within 60 seconds, across +tags" do
      described_class.call(email: "jane@getlago.com", password:)

      second = described_class.call(email: "jane+1@getlago.com", password:)

      expect(second.error).to be_a(BaseService::MethodNotAllowedFailure)
      expect(second.error.code).to eq("too_many_requests")
      expect(PendingSignup.count).to eq(1)
    end

    it "refuses the fourth email to the mailbox within an hour" do
      3.times do |minute|
        travel_to(minute.minutes.from_now) { described_class.call(email: "jane@getlago.com", password:) }
      end

      travel_to(4.minutes.from_now) do
        expect(described_class.call(email: "jane@getlago.com", password:).error.code).to eq("too_many_requests")
      end
    end

    context "when the throttling Redis is down" do
      let(:cache) { ActiveSupport::Cache::NullStore.new }

      it "still refuses from the database history" do
        create(:pending_signup, email: "jane@getlago.com", emails_sent_at: [10.seconds.ago])

        expect(result.error.code).to eq("too_many_requests")
        expect(BCrypt::Password).not_to have_received(:create).with(password, anything)
      end
    end

    context "when only Redis has counted" do
      it "refuses from Redis" do
        Auth::AttemptsThrottle.hit!(:signup_email_per_minute, "jane@getlago.com")

        expect(result.error.code).to eq("too_many_requests")
        expect(PendingSignup.count).to eq(0)
      end
    end
  end

  context "with an earlier attempt for the address" do
    let!(:earlier) { create(:pending_signup, email: "jane@getlago.com", emails_sent_at: [2.minutes.ago]) }
    let!(:earlier_token) { create(:pending_signup_token, pending_signup: earlier) }

    it "creates a separate attempt and leaves the earlier one untouched" do
      expect { result }.not_to change { earlier.reload.attributes }

      expect(PendingSignup.count).to eq(2)
      expect(earlier_token.reload).to be_pending
    end
  end

  context "when another request holds the mailbox", transaction: false do
    it "fails with lock_acquisition_failed and stores nothing" do
      stub_const("BaseLockService::ACQUIRE_LOCK_TIMEOUT", 0.seconds)

      with_email_lock("jane@getlago.com") do
        expect(result.error.code).to eq("lock_acquisition_failed")
      end

      expect(PendingSignup.count).to eq(0)
    end
  end
end
