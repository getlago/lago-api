# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessAllSubscriptionActivitiesService, type: :service do
  describe "#call" do
    subject(:service) { described_class.new }

    before do
      allow(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to receive(:perform_later)
    end

    it "enqueues ProcessOrganizationSubscriptionActivitiesJob for organizations with activity tracking" do
      organization1 = create(:organization, premium_integrations: Organization::INTEGRATIONS_TRACKING_ACTIVITY)
      organization2 = create(:organization, premium_integrations: Organization::INTEGRATIONS_TRACKING_ACTIVITY)
      organization3 = create(:organization, premium_integrations: ["salesforce"]) # No activity tracking

      result = service.call

      expect(result).to be_success
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_received(:perform_later).with(organization1)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_received(:perform_later).with(organization2)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_received(:perform_later).with(organization3)
    end

    context "when there are no organizations with activity tracking" do
      it "does not enqueue any jobs" do
        create(:organization, premium_integrations: ["salesforce"])

        service.call

        expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_received(:perform_later)
      end
    end
  end
end
