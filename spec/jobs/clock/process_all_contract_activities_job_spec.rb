# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ProcessAllContractActivitiesJob, job: true do
  subject(:perform) { described_class.perform_now }

  let_it_be(:organization) { create(:organization) }

  before { create(:contract_activity, organization:) }

  # Without arguments its lock key never changes, so a lock left by another run would hide a second enqueue
  it "runs one at a time" do
    expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuted)
    expect(described_class.lock_options).to eq(on_conflict: :log)
  end

  context "with a premium license", :premium do
    it "enqueues the job of each organization with contract activities waiting" do
      perform

      expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).to have_been_enqueued.once.with(organization.id)
    end
  end

  context "without a premium license" do
    it "enqueues no job" do
      perform

      expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued
    end
  end
end
