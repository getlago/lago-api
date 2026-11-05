# frozen_string_literal: true

require "rails_helper"

describe Clock::PendingSignupsCleanupJob do
  subject(:cleanup_job) { described_class }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    before { freeze_time }

    it "drops the password digest of attempts whose last link has expired" do
      ended = create(:pending_signup, expires_at: PendingSignupToken::TTL.ago - 1.second)
      open = create(:pending_signup, expires_at: PendingSignupToken::TTL.ago)

      cleanup_job.perform_now

      expect(ended.reload).to have_attributes(password_digest: nil, closed_at: Time.current)
      expect(open.reload).to have_attributes(password_digest: be_present, closed_at: nil)
    end

    it "deletes links a week after they expire" do
      kept = create(:pending_signup_token, expires_at: 7.days.ago)
      create(:pending_signup_token, expires_at: 7.days.ago - 1.second)

      cleanup_job.perform_now

      expect(PendingSignupToken.all).to eq([kept])
    end

    it "deletes attempts 9 days after Step 1, with their links, even when updated since" do
      old = create(:pending_signup, created_at: 9.days.ago - 1.second, updated_at: 1.day.ago)
      create(:pending_signup_token, pending_signup: old, expires_at: 1.day.from_now)
      kept = create(:pending_signup, created_at: 9.days.ago)

      cleanup_job.perform_now

      expect(PendingSignup.all).to eq([kept])
      expect(PendingSignupToken.count).to eq(0)
    end

    it "deletes more rows than one batch" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      create_list(:pending_signup, 3, created_at: 10.days.ago)

      expect { cleanup_job.perform_now }.to change(PendingSignup, :count).to(0)
    end

    it "keeps going until every ended attempt of a larger batch is closed" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      ended = create_list(:pending_signup, 3, expires_at: PendingSignupToken::TTL.ago - 1.second)

      cleanup_job.perform_now

      expect(ended.map { it.reload.password_digest }).to eq([nil, nil, nil])
    end
  end
end
