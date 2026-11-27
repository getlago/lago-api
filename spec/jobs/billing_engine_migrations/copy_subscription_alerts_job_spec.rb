# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopySubscriptionAlertsJob do
  subject(:copy_job) { described_class }

  let(:migration) { create(:billing_engine_migration) }
  let(:subscription) { create(:subscription, organization: migration.organization) }

  before { allow(BillingEngineMigrations::CopySubscriptionAlertsService).to receive(:call!) }

  it_behaves_like "a unique job" do
    let(:job_args) { [migration.id, subscription] }
  end

  it "copies the alerts of the subscription" do
    copy_job.perform_now(migration.id, subscription)

    expect(BillingEngineMigrations::CopySubscriptionAlertsService).to have_received(:call!).with(migration:, subscription:)
  end

  context "when the migration no longer exists" do
    it "does nothing" do
      copy_job.perform_now(SecureRandom.uuid, subscription)

      expect(BillingEngineMigrations::CopySubscriptionAlertsService).not_to have_received(:call!)
    end
  end

  context "when a lock of the service cannot be acquired" do
    before do
      allow(BillingEngineMigrations::CopySubscriptionAlertsService).to receive(:call!).and_raise(
        BaseService::LockAcquisitionFailure.new(BaseService::Result.new, code: "lock_acquisition_failed", error_message: "locked")
      )
    end

    it "retries the copy" do
      expect { copy_job.perform_now(migration.id, subscription) }.to have_enqueued_job(described_class).with(migration.id, subscription)
    end
  end

  context "when another copy of the subscription is running" do
    before do
      allow(BillingEngineMigrations::CopySubscriptionAlertsService).to receive(:call!)
        .and_raise(BaseLockService::FailedToAcquireLock, "Failed to acquire lock")
    end

    it "retries the copy" do
      expect { copy_job.perform_now(migration.id, subscription) }.to have_enqueued_job(described_class).with(migration.id, subscription)
    end
  end

  context "when the copy fails" do
    let(:failure) do
      BaseService::Result.new.single_validation_failure!(field: :thresholds, error_code: "value_is_invalid").error
    end

    before { allow(BillingEngineMigrations::CopySubscriptionAlertsService).to receive(:call!).and_raise(failure) }

    it "raises without retrying" do
      expect { copy_job.perform_now(migration.id, subscription) }
        .to raise_error(BaseService::ValidationFailure)
        .and not_have_enqueued_job(described_class)
    end
  end
end
