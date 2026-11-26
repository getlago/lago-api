# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessAllContractActivitiesService do
  subject(:result) { described_class.call }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }

  it "enqueues one job per organization with contract activities waiting" do
    create_list(:contract_activity, 2, organization:)
    create(:contract_activity, organization: other_organization)

    expect(result).to be_success
    expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).to have_been_enqueued.once.with(organization.id)
    expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).to have_been_enqueued.once.with(other_organization.id)
  end

  context "when the contract activities of an organization are all enqueued" do
    before do
      create(:contract_activity, organization:, enqueued: true, enqueued_at: Time.current)
      create(:contract_activity, organization: other_organization)
    end

    it "enqueues no job for it" do
      result

      expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued.with(organization.id)
      expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).to have_been_enqueued.once.with(other_organization.id)
    end
  end

  context "when only subscriptions are active" do
    before { create(:subscription_activity, organization:) }

    it "enqueues no job" do
      expect(result).to be_success
      expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued
    end
  end

  context "without contract activities" do
    it "enqueues no job" do
      expect(result).to be_success
      expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued
    end
  end

  context "when an organization is on a dedicated worker" do
    before do
      stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [organization.id])
      create(:contract_activity, organization:)
      create(:contract_activity, organization: other_organization)
    end

    it "leaves it to the dedicated sweep" do
      result

      expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued.with(organization.id)
      expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).to have_been_enqueued.once.with(other_organization.id)
    end
  end
end
