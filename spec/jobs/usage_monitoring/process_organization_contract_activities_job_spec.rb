# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessOrganizationContractActivitiesJob do
  subject(:perform) { described_class.perform_now(organization.id) }

  let_it_be(:organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }

  let(:contract_activity) { create(:contract_activity, organization:) }

  before { contract_activity }

  it_behaves_like "a configurable queue", "alerts", "SIDEKIQ_ALERTS" do
    let(:arguments) { organization.id }
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [organization.id] }
  end

  context "with a premium license", :premium do
    it "enqueues the job of each contract activity waiting" do
      perform

      expect(UsageMonitoring::ProcessContractActivityJob).to have_been_enqueued.once.with(contract_activity.id)
      expect(contract_activity.reload.enqueued).to be(true)
    end

    context "without the contract_alerts flag" do
      subject(:perform) { described_class.perform_now(unflagged_organization.id) }

      let(:unflagged_organization) { create(:organization, feature_flags: %w[product_catalog]) }
      let(:contract_activity) { create(:contract_activity, organization: unflagged_organization) }

      it "enqueues no job" do
        perform

        expect(UsageMonitoring::ProcessContractActivityJob).not_to have_been_enqueued
        expect(UsageMonitoring::ContractActivity.where(id: contract_activity.id)).not_to exist
      end
    end
  end

  context "without a premium license" do
    it "enqueues no job" do
      perform

      expect(UsageMonitoring::ProcessContractActivityJob).not_to have_been_enqueued
      expect(contract_activity.reload.enqueued).to be(false)
    end
  end

  describe "queue routing" do
    before { stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [organization.id]) }

    it "routes an organization on a dedicated worker to the dedicated queue" do
      expect(described_class.new(organization.id).queue_name).to eq("dedicated_alerts")
    end

    it "routes another organization to the default queue" do
      expect(described_class.new(create(:organization).id).queue_name).to eq("default")
    end
  end
end
