# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopySubscriptionJob do
  subject(:copy_job) { described_class }

  let(:migration) { create(:billing_engine_migration) }
  let(:subscription) { create(:subscription, organization: migration.organization) }

  before { allow(BillingEngineMigrations::CopySubscriptionService).to receive(:call!) }

  it_behaves_like "a unique job" do
    let(:job_args) { [subscription] }
  end

  it "copies the subscription with the migration of its organization" do
    copy_job.perform_now(subscription)

    expect(BillingEngineMigrations::CopySubscriptionService).to have_received(:call!).with(migration:, subscription:)
  end

  context "when the organization has no migration" do
    let(:subscription) { create(:subscription) }

    it "does nothing" do
      copy_job.perform_now(subscription)

      expect(BillingEngineMigrations::CopySubscriptionService).not_to have_received(:call!)
    end
  end

  context "when the billing schedule of the shadow customer is locked" do
    before do
      allow(BillingEngineMigrations::CopySubscriptionService).to receive(:call!).and_raise(
        BaseService::LockAcquisitionFailure.new(BaseService::Result.new, code: "lock_acquisition_failed", error_message: "locked")
      )
    end

    it "retries the copy" do
      expect { copy_job.perform_now(subscription) }.to have_enqueued_job(described_class).with(subscription)
    end
  end

  context "when the copy fails" do
    let(:failure) do
      BaseService::Result.new.single_validation_failure!(field: :plan_code, error_code: "value_is_invalid").error
    end

    before { allow(BillingEngineMigrations::CopySubscriptionService).to receive(:call!).and_raise(failure) }

    it "raises without retrying" do
      expect { copy_job.perform_now(subscription) }
        .to raise_error(BaseService::ValidationFailure)
        .and not_have_enqueued_job(described_class)
    end
  end
end
