# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessSubscriptionActivityService, type: :service do
  subject(:service) { described_class.new(subscription_activity:) }

  let(:organization) { create(:organization, premium_integrations:) }
  let(:mocked_current_usage) { double("current_usage") } # rubocop:disable RSpec/VerifiedDoubles
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let!(:subscription_activity) { create(:subscription_activity, subscription:) }

  before do
    allow(::Invoices::CustomerUsageService).to receive(:call)
      .and_return(double(usage: mocked_current_usage)) # rubocop:disable RSpec/VerifiedDoubles
    allow(LifetimeUsages::CalculateService).to receive(:call!)
    allow(LifetimeUsages::CheckThresholdsService).to receive(:call)
  end

  around { |test| lago_premium!(&test) }

  context "when both lifetime_usage and progressive_billing are enabled" do
    let(:premium_integrations) { Organization::INTEGRATIONS_TRACKING_ACTIVITY }

    it "calls both services and deletes subscription_activity" do
      expect(LifetimeUsages::CalculateService).to receive(:call!).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage),
        current_usage: mocked_current_usage
      )
      expect(LifetimeUsages::CheckThresholdsService).to receive(:call).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage)
      )

      result = service.call

      expect(result).to be_success
      expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "when lifetime_usage and progressive_billing are both disabled" do
    let(:premium_integrations) { ["salesforce"] }

    it "calculates and checks thresholds are not called" do
      expect(LifetimeUsages::CalculateService).not_to receive(:call!)
      expect(LifetimeUsages::CheckThresholdsService).not_to receive(:call)

      result = service.call

      expect(result).to be_success
      expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound) # deleted
    end

    it "creates a lifetime usage if does not exist" do
      subscription.lifetime_usage&.delete
      expect { service.call }.to change { subscription.reload.lifetime_usage.present? }.from(false).to(true)
    end
  end

  context "when only using lifetime_usage" do
    let(:premium_integrations) { ["lifetime_usage"] }

    it "calls calculate service and deletes subscription_activity" do
      expect(LifetimeUsages::CalculateService).to receive(:call!).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage),
        current_usage: mocked_current_usage
      )
      expect(LifetimeUsages::CheckThresholdsService).not_to receive(:call)

      result = service.call

      expect(result).to be_success
      expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "when progressive_billing_enabled is true" do
    let(:premium_integrations) { ["progressive_billing"] }

    it "calls both calculate and check thresholds services and deletes subscription_activity" do
      expect(LifetimeUsages::CalculateService).to receive(:call!).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage),
        current_usage: mocked_current_usage
      )
      expect(LifetimeUsages::CheckThresholdsService).to receive(:call).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage)
      )

      result = service.call

      expect(result).to be_success
      expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "when lifetime_usage already exists" do
    let(:premium_integrations) { Organization::INTEGRATIONS_TRACKING_ACTIVITY }

    it "does not create a new lifetime usage" do
      create(:lifetime_usage, subscription: subscription, organization: organization)
      expect { service.call }.not_to change(LifetimeUsage, :count)
    end
  end
end
