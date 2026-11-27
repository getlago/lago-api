# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessOrganizationContractActivitiesService do
  subject(:result) { described_class.call(organization:) }

  let_it_be(:organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }

  before { freeze_time }

  it "enqueues one job per contract activity waiting, after marking them enqueued" do
    waiting = create_list(:contract_activity, 3, organization:)
    already_enqueued = create_list(:contract_activity, 2, organization:, enqueued: true, enqueued_at: 1.minute.ago)

    expect { result }.to have_enqueued_job_after_commit(UsageMonitoring::ProcessContractActivityJob).exactly(3).times

    expect(result).to be_success
    expect(result.nb_jobs_enqueued).to eq(3)
    waiting.each do |contract_activity|
      expect(UsageMonitoring::ProcessContractActivityJob).to have_been_enqueued.with(contract_activity.id)
      expect(contract_activity.reload).to have_attributes(enqueued: true, enqueued_at: Time.current)
    end
    already_enqueued.each do |contract_activity|
      expect(UsageMonitoring::ProcessContractActivityJob).not_to have_been_enqueued.with(contract_activity.id)
      expect(contract_activity.reload.enqueued_at).to eq(1.minute.ago)
    end
  end

  context "with contract activities of another organization" do
    let(:other_contract_activity) { create(:contract_activity, organization: create(:organization)) }

    before do
      other_contract_activity
      create(:contract_activity, organization:)
    end

    it "leaves them for their organization" do
      expect(result.nb_jobs_enqueued).to eq(1)
      expect(UsageMonitoring::ProcessContractActivityJob).not_to have_been_enqueued.with(other_contract_activity.id)
      expect(other_contract_activity.reload).to have_attributes(enqueued: false, enqueued_at: nil)
    end
  end

  context "when the contract_alerts flag was turned off after its contracts were tracked" do
    subject(:result) { described_class.call(organization: unflagged_organization) }

    let(:unflagged_organization) { create(:organization, feature_flags: %w[product_catalog]) }
    let(:waiting) { create(:contract_activity, organization: unflagged_organization) }
    let(:already_enqueued) { create(:contract_activity, organization: unflagged_organization, enqueued: true, enqueued_at: 1.minute.ago) }
    let(:other_organization_waiting) { create(:contract_activity, organization:) }

    before do
      waiting
      already_enqueued
      other_organization_waiting
    end

    it "enqueues no job and drops the contract activities waiting, so the clock stops picking it up" do
      expect { result }.not_to have_enqueued_job(UsageMonitoring::ProcessContractActivityJob)

      expect(result).to be_success
      expect(result.nb_jobs_enqueued).to eq(0)
      expect(UsageMonitoring::ContractActivity.where(id: waiting.id)).not_to exist
      expect(UsageMonitoring::ContractActivity.where(enqueued: false).pluck(:organization_id)).to eq([organization.id])
    end

    it "leaves the contract activity already enqueued to its job" do
      result

      expect(already_enqueued.reload).to have_attributes(enqueued: true, enqueued_at: 1.minute.ago)
    end
  end

  context "without contract activities waiting" do
    before { create(:contract_activity, organization:, enqueued: true, enqueued_at: 1.minute.ago) }

    it "enqueues no job" do
      expect { result }.not_to have_enqueued_job(UsageMonitoring::ProcessContractActivityJob)
      expect(result.nb_jobs_enqueued).to eq(0)
    end
  end

  context "with more contract activities than a batch" do
    before do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      create_list(:contract_activity, 3, organization:)
    end

    it "enqueues them all, batch by batch" do
      expect { result }.to have_enqueued_job(UsageMonitoring::ProcessContractActivityJob).exactly(3).times
      expect(result.nb_jobs_enqueued).to eq(3)
      expect(organization.contract_activities.where(enqueued: false)).to be_empty
    end
  end

  context "when the organization is on a dedicated worker" do
    before do
      stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [organization.id])
      create_list(:contract_activity, 2, organization:)
    end

    it "enqueues the jobs on the dedicated queue" do
      expect { result }
        .to have_enqueued_job(UsageMonitoring::ProcessContractActivityJob).on_queue("dedicated_alerts").exactly(2).times
    end
  end

  context "when the alerts queue is enabled" do
    before do
      stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [])
      ENV["SIDEKIQ_ALERTS"] = "true"
      create(:contract_activity, organization:)
    end

    after { ENV.delete("SIDEKIQ_ALERTS") }

    it "enqueues the jobs on the alerts queue" do
      expect { result }.to have_enqueued_job(UsageMonitoring::ProcessContractActivityJob).on_queue("alerts").once
    end
  end

  context "without a dedicated worker or the alerts queue" do
    before do
      stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [])
      create(:contract_activity, organization:)
    end

    it "enqueues the jobs on the default queue" do
      expect { result }.to have_enqueued_job(UsageMonitoring::ProcessContractActivityJob).on_queue("default").once
    end
  end
end
