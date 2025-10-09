# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::TrackSubscriptionActivityService do
  subject { described_class.new(organization:, subscription:) }

  let(:organization) { create(:organization, premium_integrations: %w[lifetime_usage]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  around { |test| lago_premium!(&test) }

  context "when the plan has usage_thresholds" do
    it "tracks activity" do
      create(:usage_threshold, plan: subscription.plan)
      expect { subject.call }.to change { organization.subscription_activities.count }.by(1)
      expect { subject.call }.to change { organization.subscription_activities.count }.by(0)
    end
  end

  context "when organization does use any integration with subscription tracking" do
    let(:organization) { create(:organization, premium_integrations: %w[salesforce]) }

    it "does not track activity" do
      subject.call
      expect(organization.subscription_activities.count).to eq(0)
    end
  end

  context "when subscription isn't active" do
    let(:subscription) { create(:subscription, :terminated, customer:) }

    it "does not track activity" do
      subject.call
      expect(organization.subscription_activities.count).to eq(0)
    end
  end
end
