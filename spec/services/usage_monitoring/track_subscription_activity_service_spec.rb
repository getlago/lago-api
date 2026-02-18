# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::TrackSubscriptionActivityService, :premium do
  subject { described_class.new(organization:, subscription:) }

  let(:organization) { create(:organization, premium_integrations: %w[lifetime_usage]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  context "when the plan has usage_thresholds" do
    it "tracks activity" do
      create(:usage_threshold, plan: subscription.plan)
      expect { subject.call }.to change { organization.subscription_activities.count }.by(1)
      expect { subject.call }.not_to change { organization.subscription_activities.count }
    end

    it "sets renew_daily_usage to true" do
      create(:usage_threshold, plan: subscription.plan)
      expect { subject.call }.to change { subscription.reload.renew_daily_usage }.from(false).to(true)
    end
  end

  context "when organization does use any integration with subscription tracking" do
    let(:organization) { create(:organization, premium_integrations: %w[salesforce]) }

    it "does not track activity" do
      subject.call
      expect(organization.subscription_activities.count).to eq(0)
    end

    it "still sets renew_daily_usage to true" do
      expect { subject.call }.to change { subscription.reload.renew_daily_usage }.from(false).to(true)
    end
  end

  context "when subscription isn't active" do
    let(:subscription) { create(:subscription, :terminated, customer:) }

    it "does not track activity" do
      subject.call
      expect(organization.subscription_activities.count).to eq(0)
    end

    it "does not set renew_daily_usage" do
      subject.call
      expect(subscription.reload.renew_daily_usage).to be(false)
    end
  end

  context "when license is not premium" do
    it "does not set renew_daily_usage" do
      allow(License).to receive(:premium?).and_return(false)
      subject.call
      expect(subscription.reload.renew_daily_usage).to be(false)
    end
  end
end
