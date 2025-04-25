# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::TrackSubscriptionActivityService, type: :service do
  subject { described_class.new(organization:, subscription_ids: [subscription.id]) }

  let(:organization) { create(:organization, premium_integrations: Organization::INTEGRATIONS_TRACKING_ACTIVITY) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  around { |test| lago_premium!(&test) }

  it "tracks activity" do
    expect { subject.call }.to change { organization.subscription_activities.count }.by(1)
    expect { subject.call }.to change { organization.subscription_activities.count }.by(0)
  end

  context "when organization does use any integration with subscription tracking" do
    let(:organization) { create(:organization, premium_integrations: %w[salesforce]) }

    it "does not track activity" do
      expect(organization.subscription_activities.count).to eq(0)
    end
  end
end
