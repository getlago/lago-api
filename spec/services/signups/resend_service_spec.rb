# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::ResendService do
  subject(:result) { described_class.call(signup_secret:) }

  # Before the records below are created, so their send times have no sub-seconds.
  before { freeze_time }

  include_context "with self-serve enabled"

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:, emails_sent_at: [2.minutes.ago]) }
  let(:token) { PendingSignupToken.generate }
  let!(:token_record) { create(:pending_signup_token, pending_signup:, token:) }

  it "records the send and enqueues the delivery with the attempt id only" do
    expect { result }.to have_enqueued_job_after_commit(Signups::DeliverVerificationJob).with(pending_signup.id)

    expect(pending_signup.reload.emails_sent_at.size).to eq(2)
    expect([result.resend_available_in_seconds, result.resend_limit_reached]).to eq([60, false])
  end

  it "replaces the attempt's previous link and leaves other attempts alone" do
    other_token = create(:pending_signup_token, pending_signup: create(:pending_signup, email: "jane@getlago.com", emails_sent_at: [10.minutes.ago]))

    result
    perform_enqueued_jobs

    expect(token_record.reload.verification_status).to eq(:replaced)
    expect(pending_signup.tokens.pending.count).to eq(1)
    expect(other_token.reload).to be_pending
  end

  it "accepts a replaced or locked link of the attempt" do
    [{status: "replaced"}, {failed_password_attempts: 5}].each do |attributes|
      pending_signup.reload.update!(emails_sent_at: [2.minutes.ago])
      token_record.update!(attributes)

      expect(described_class.call(token:)).to be_success
    end
  end

  it "answers signup_expired for an expired link, whose attempt is past its window too" do
    pending_signup.update!(expires_at: 1.second.ago)
    token_record.update!(expires_at: 1.second.ago)

    expect(described_class.call(token:).error.code).to eq("signup_expired")
  end

  it "keeps the attempt's life and purge date" do
    expect { result }.not_to change { pending_signup.reload.slice(:expires_at, :created_at) }
  end

  context "when the address already has a user" do
    before { create(:user, email: "jane@getlago.com") }

    it "answers the same and sends the account-exists email" do
      expect([result.resend_available_in_seconds, result.resend_limit_reached]).to eq([60, false])

      perform_enqueued_jobs

      expect(ActionMailer::Base.deliveries.last.subject).to eq("You already have a Lago account")
    end
  end

  describe "refusals of the attempt" do
    it "refuses a confirmed signup" do
      token_record.update!(status: "consumed", consumed_at: Time.current)

      expect(described_class.call(token:).error.code).to eq("email_already_verified")
    end

    it "refuses an unknown secret or link, and a call without either" do
      expect(described_class.call(signup_secret: PendingSignup.generate_signup_secret).error.resource).to eq("pending_signup")
      expect(described_class.call(token: PendingSignupToken.generate).error.resource).to eq("pending_signup")
      expect(described_class.call.error.messages).to eq(signup_secret: ["value_is_mandatory"])
    end

    it "refuses the attempt's fourth email, even once the mailbox window frees" do
      pending_signup.update!(emails_sent_at: [3.hours.ago, 3.hours.ago, 3.hours.ago])

      expect(result.error.code).to eq("signup_resend_exhausted")
    end

    it "refuses 24 hours after Step 1" do
      pending_signup.update!(expires_at: Time.current)

      expect(result.error.code).to eq("signup_expired")
    end
  end

  context "when the email lock is not acquired" do
    before do
      Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
      allow(Users::EmailLockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock)
    end

    it "answers lock_acquisition_failed, with nothing sent or counted" do
      expect(result.error.code).to eq("lock_acquisition_failed")
      expect(pending_signup.reload.emails_sent_at.size).to eq(1)
      expect(Auth::AttemptsThrottle.at_limit?(:signup_email_per_minute, "jane@getlago.com")).to be(false)
      expect(Signups::DeliverVerificationJob).not_to have_been_enqueued
    end
  end

  describe "mailbox limits" do
    let(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:, emails_sent_at: [20.seconds.ago]) }

    it "refuses within 60 seconds, with the seconds left" do
      expect(result.error.code).to eq("resend_too_soon")
      expect(result.retry_after_seconds).to eq(40)
      expect(Signups::DeliverVerificationJob).not_to have_been_enqueued
    end

    context "with 3 emails to the mailbox in the hour, across +tags" do
      let(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:, emails_sent_at: [50.minutes.ago]) }

      before { create(:pending_signup, email: "jane+x@getlago.com", emails_sent_at: [40.minutes.ago, 30.minutes.ago]) }

      it "refuses until the oldest leaves the hour" do
        expect(result.error.code).to eq("resend_limit_reached")
        expect(result.retry_after_seconds).to eq(10.minutes.to_i) # the email of 50 minutes ago leaves the hour in 10
      end

      context "when the attempt's window closes before then" do
        let(:pending_signup) do
          create(:pending_signup, email: "jane@getlago.com", signup_secret:, emails_sent_at: [50.minutes.ago], expires_at: 10.minutes.from_now)
        end

        it "answers that the attempt can send no more" do
          expect([result.error.code, result.retry_after_seconds]).to eq(["signup_resend_exhausted", nil])
          expect(Signups::DeliverVerificationJob).not_to have_been_enqueued
        end
      end
    end

    context "when the throttling Redis is down" do
      before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::NullStore.new }

      it "still refuses from the database history" do
        expect(result.error.code).to eq("resend_too_soon")
      end
    end

    context "when only Redis has counted, as for an attempt that failed before sending" do
      let(:pending_signup) do
        create(:pending_signup, email: "jane@getlago.com", signup_secret:, emails_sent_at: [10.minutes.ago], expires_at: 30.minutes.from_now)
      end

      before do
        Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
        3.times { Auth::AttemptsThrottle.hit!(:signup_email_per_hour, "jane@getlago.com") }
      end

      it "sends, as the database history allows it" do
        expect(result).to be_success
        expect(pending_signup.reload.emails_sent_at.size).to eq(2)
      end
    end

    context "with the throttling Redis" do
      before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new }

      it "counts the send once it is committed, for Step 1" do
        result

        expect(Auth::AttemptsThrottle.at_limit?(:signup_email_per_minute, "jane@getlago.com")).to be(true)
      end

      it "counts nothing for a refused resend" do
        pending_signup.update!(emails_sent_at: [20.seconds.ago])

        result

        expect(Auth::AttemptsThrottle.at_limit?(:signup_email_per_minute, "jane@getlago.com")).to be(false)
      end
    end
  end
end
