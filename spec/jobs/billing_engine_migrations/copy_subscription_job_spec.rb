# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopySubscriptionJob do
  subject(:copy_job) { described_class }

  let(:migration) { create(:billing_engine_migration) }
  let(:subscription) { create(:subscription, organization: migration.organization) }

  before { allow(BillingEngineMigrations::CopySubscriptionService).to receive(:call) }

  it_behaves_like "a unique job" do
    let(:job_args) { [migration, subscription] }
  end

  it "copies the subscription" do
    copy_job.perform_now(migration, subscription)

    expect(BillingEngineMigrations::CopySubscriptionService).to have_received(:call).with(migration:, subscription:)
  end
end
