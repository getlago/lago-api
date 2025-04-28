# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessAllSubscriptionActivitiesService, type: :service do
  describe "#call" do
    subject(:service) { described_class.new }

    before do
      allow(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to receive(:perform_later)
    end

    it "enqueues ProcessOrganizationSubscriptionActivitiesJob for all organizations" do
      organization1 = create(:organization, premium_integrations: [])
      organization2 = create(:organization, premium_integrations: ["progressive_billing"])
      organization3 = create(:organization, premium_integrations: ["salesforce"])

      result = service.call

      expect(result).to be_success
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_received(:perform_later).with(organization1.id)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_received(:perform_later).with(organization2.id)
      expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_received(:perform_later).with(organization3.id)
    end
  end
end
