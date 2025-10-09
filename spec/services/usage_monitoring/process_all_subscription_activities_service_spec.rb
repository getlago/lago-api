# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessAllSubscriptionActivitiesService do
  describe "#call" do
    subject(:service) { described_class.new }

    before do
      allow(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to receive(:perform_later)
      allow(Rails.logger).to receive(:info)
    end

    it "enqueues ProcessOrganizationSubscriptionActivitiesJob for organizations with SubscriptionActivity" do
      organization1 = create(:organization, premium_integrations: [])
      organization2 = create(:organization, premium_integrations: ["progressive_billing"])
      organization3 = create(:organization, premium_integrations: ["salesforce"])
      create_list(:subscription_activity, 2, organization: organization1)
      create_list(:subscription_activity, 3, organization: organization2)

      result = service.call

      expect(result).to be_success
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_received(:perform_later).with(organization1.id)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_received(:perform_later).with(organization2.id)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_received(:perform_later).with(organization3.id)
    end
  end
end
