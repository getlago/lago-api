# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob, type: :job do
  let(:organization) { create(:organization) }

  before do
    allow(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService).to receive(:call!)
  end

  context "when license is premium" do
    around { |test| lago_premium!(&test) }

    it "calls the service with the organization" do
      described_class.perform_now(organization.id)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService).to have_received(:call!).with(organization:)
    end
  end

  context "when license is not premium" do
    it "does not call the service or log" do
      described_class.perform_now(organization.id)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService).not_to have_received(:call!)
    end
  end
end
