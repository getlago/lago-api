# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyCustomerJob do
  subject(:copy_job) { described_class }

  let(:customer) { create(:customer) }
  let(:migration) { create(:billing_engine_migration, organization: customer.organization) }

  before { allow(BillingEngineMigrations::CopyCustomerService).to receive(:call!) }

  it_behaves_like "a unique job" do
    let(:job_args) { [migration.id, customer.id] }
  end

  it "copies the customer" do
    copy_job.perform_now(migration.id, customer.id)

    expect(BillingEngineMigrations::CopyCustomerService).to have_received(:call!).with(migration:, customer:)
  end

  context "when the customer was deleted since" do
    before { customer.discard! }

    it "does nothing" do
      copy_job.perform_now(migration.id, customer.id)

      expect(BillingEngineMigrations::CopyCustomerService).not_to have_received(:call!)
    end
  end

  context "when another copy of the customer holds the lock" do
    before do
      allow(BillingEngineMigrations::CopyCustomerService).to receive(:call!)
        .and_raise(BaseLockService::FailedToAcquireLock, "Failed to acquire lock")
    end

    it "retries the copy" do
      expect { copy_job.perform_now(migration.id, customer.id) }
        .to have_enqueued_job(described_class).with(migration.id, customer.id)
    end
  end

  context "when the copy fails" do
    let(:failure) do
      BaseService::Result.new.service_failure!(code: "shadow_organization_not_isolated", message: "not isolated").error
    end

    before { allow(BillingEngineMigrations::CopyCustomerService).to receive(:call!).and_raise(failure) }

    it "raises without retrying" do
      expect { copy_job.perform_now(migration.id, customer.id) }
        .to raise_error(BaseService::ServiceFailure)
        .and not_have_enqueued_job(described_class)
    end
  end
end
