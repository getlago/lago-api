# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob, type: :job do
  let(:organization) { create(:organization) }
  let(:result_double) { instance_double("UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService::Result", nb_jobs_enqueued: 5) }

  before do
    allow(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService).to receive(:call!).and_return(result_double)
    allow(Rails.logger).to receive(:info)
  end

  context "when license is premium" do
    around { |test| lago_premium!(&test) }

    it "calls the service with the organization" do
      described_class.perform_now(organization)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService).to have_received(:call!).with(organization:)
    end

    it "logs the number of jobs enqueued" do
      described_class.perform_now(organization)
      expect(Rails.logger).to have_received(:info).with("[#{organization.id}] ProcessOrganizationSubscriptionActivitiesService enqueued 5 jobs")
    end
  end

  context "when license is not premium" do
    it "does not call the service or log" do
      described_class.perform_now(organization)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService).not_to have_received(:call!)
      expect(Rails.logger).not_to have_received(:info)
    end
  end
end
