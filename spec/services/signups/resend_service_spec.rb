# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::ResendService do
  subject(:result) { described_class.call(signup_secret:) }

  # Before the records below are created, so their send times have no sub-seconds.
  before do
    freeze_time
    token_record
  end

  include_context "with self-serve enabled"

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:emails_sent_at) { [2.minutes.ago] }
  let(:expires_at) { 22.hours.from_now }
  let(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:, emails_sent_at:, expires_at:) }
  let(:token) { PendingSignupToken.generate }
  let(:token_attributes) { {} }
  let(:token_record) { create(:pending_signup_token, pending_signup:, token:, **token_attributes) }

  it "records the send and enqueues the delivery with the attempt id only" do
    expect { result }.to have_enqueued_job_after_commit(Signups::DeliverVerificationJob).with(pending_signup.id)

    expect(pending_signup.reload.emails_sent_at.size).to eq(2)
    expect([result.resend_available_in_seconds, result.resend_limit_reached]).to eq([60, false])
  end

  it "keeps the attempt's life and purge date" do
    expect { result }.not_to change { pending_signup.reload.slice(:expires_at, :created_at) }
  end

  context "with another attempt to the same address" do
    let(:other_token) do
      create(:pending_signup_token, pending_signup: create(:pending_signup, email: "jane@getlago.com", emails_sent_at: [10.minutes.ago]))
    end

    before { other_token }

    it "replaces the attempt's previous link and leaves the other attempt alone" do
      result
      perform_enqueued_jobs

      expect(token_record.reload.verification_status).to eq(:replaced)
      expect(pending_signup.tokens.pending.count).to eq(1)
      expect(other_token.reload).to be_pending
    end
  end

  [{status: "replaced"}, {failed_password_attempts: 5}].each do |attributes|
    context "with a #{attributes.keys.first} link of the attempt" do
      subject(:result) { described_class.call(token:) }

      let(:token_attributes) { attributes }

      it { is_expected.to be_success }
    end
  end

  context "with a link and the secret of another attempt, as from a tab of another signup" do
    subject(:result) { described_class.call(signup_secret: other_secret, token:) }

    let(:other_secret) { PendingSignup.generate_signup_secret }
    let(:other_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret: other_secret, emails_sent_at: [10.minutes.ago]) }

    before { other_signup }

    it "resends the link's attempt" do
      expect(result).to be_success
      expect(pending_signup.reload.emails_sent_at.size).to eq(2)
      expect(other_signup.reload.emails_sent_at.size).to eq(1)
    end

    context "when the secret matches no attempt" do
      let(:other_secret) { "garbage" }
      let(:other_signup) { nil }

      it "resends the link's attempt" do
        expect(result).to be_success
        expect(pending_signup.reload.emails_sent_at.size).to eq(2)
      end
    end
  end

  context "with an expired link, whose attempt is past its window too" do
    subject(:result) { described_class.call(token:) }

    let(:expires_at) { 1.second.ago }
    let(:token_attributes) { {expires_at: 1.second.ago} }

    it "answers signup_expired" do
      expect(result.error.code).to eq("signup_expired")
    end
  end

  context "when the address already has a user" do
    before { create(:user, email: "jane@getlago.com") }

    it "answers the same and sends the account-exists email" do
      expect([result.resend_available_in_seconds, result.resend_limit_reached]).to eq([60, false])

      perform_enqueued_jobs

      expect(ActionMailer::Base.deliveries.last.subject).to eq("You already have a Lago account")
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

  describe "refusals of the attempt" do
    context "with a confirmed signup" do
      subject(:result) { described_class.call(token:) }

      let(:token_attributes) { {status: "consumed", consumed_at: Time.current} }

      it "answers email_already_verified" do
        expect(result.error.code).to eq("email_already_verified")
      end
    end

    it "refuses an unknown secret or link, and a call without either" do
      expect(described_class.call(signup_secret: PendingSignup.generate_signup_secret).error.resource).to eq("pending_signup")
      expect(described_class.call(token: PendingSignupToken.generate).error.resource).to eq("pending_signup")
      expect(described_class.call.error.messages).to eq(signup_secret: ["value_is_mandatory"])
    end

    context "with a closed attempt whose address has no user" do
      let(:pending_signup) do
        create(:pending_signup, :closed, email: "jane@getlago.com", signup_secret:, emails_sent_at:, expires_at:)
      end

      it "answers signup_expired, with nothing sent or counted" do
        expect { result }.not_to have_enqueued_job(Signups::DeliverVerificationJob)

        expect(result.error.code).to eq("signup_expired")
        expect(pending_signup.reload.emails_sent_at.size).to eq(1)
      end
    end

    context "with the attempt's 3 emails sent, the mailbox window free again" do
      let(:emails_sent_at) { [3.hours.ago] * 3 }

      it "answers signup_resend_exhausted" do
        expect(result.error.code).to eq("signup_resend_exhausted")
      end
    end

    context "when 24 hours have passed since Step 1" do
      let(:expires_at) { Time.current }

      it "answers signup_expired" do
        expect(result.error.code).to eq("signup_expired")
      end
    end
  end

  describe "mailbox limits" do
    let(:emails_sent_at) { [20.seconds.ago] }

    it "refuses within 60 seconds, with the seconds left" do
      expect(result.error.code).to eq("resend_too_soon")
      expect(result.retry_after_seconds).to eq(40)
      expect(Signups::DeliverVerificationJob).not_to have_been_enqueued
    end

    context "with 3 emails to the mailbox in the hour, across +tags" do
      let(:emails_sent_at) { [50.minutes.ago] }

      before { create(:pending_signup, email: "jane+x@getlago.com", emails_sent_at: [40.minutes.ago, 30.minutes.ago]) }

      it "refuses until the oldest leaves the hour" do
        expect(result.error.code).to eq("resend_limit_reached")
        expect(result.retry_after_seconds).to eq(10.minutes.to_i) # the email of 50 minutes ago leaves the hour in 10
      end

      context "when the attempt's window closes before then" do
        let(:expires_at) { 10.minutes.from_now }

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
      let(:emails_sent_at) { [10.minutes.ago] }
      let(:expires_at) { 30.minutes.from_now }

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
      let(:emails_sent_at) { [2.minutes.ago] }

      before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new }

      it "counts the send once it is committed, for Step 1" do
        result

        expect(Auth::AttemptsThrottle.at_limit?(:signup_email_per_minute, "jane@getlago.com")).to be(true)
      end

      context "when the resend is refused" do
        let(:emails_sent_at) { [20.seconds.ago] }

        it "counts nothing" do
          result

          expect(Auth::AttemptsThrottle.at_limit?(:signup_email_per_minute, "jane@getlago.com")).to be(false)
        end
      end
    end
  end
end
