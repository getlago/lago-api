# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessSubscriptionActivityService, type: :service do
  subject(:service) { described_class.new(subscription_activity:) }

  let(:organization) { create(:organization, premium_integrations:) }
  let(:mocked_current_usage) { double("current_usage") } # rubocop:disable RSpec/VerifiedDoubles
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let!(:subscription_activity) { create(:subscription_activity, subscription:, organization:) }

  before do
    allow(::Invoices::CustomerUsageService).to receive(:call)
      .and_return(double(usage: mocked_current_usage)) # rubocop:disable RSpec/VerifiedDoubles
    allow(LifetimeUsages::CalculateService).to receive(:call!)
    allow(LifetimeUsages::CheckThresholdsService).to receive(:call)
  end

  around { |test| lago_premium!(&test) }

  context "when both lifetime_usage and progressive_billing are enabled" do
    let(:premium_integrations) { %w[lifetime_usage progressive_billing] }

    it "calls both services and deletes subscription_activity" do
      result = service.call

      expect(LifetimeUsages::CalculateService).to have_received(:call!).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage),
        current_usage: mocked_current_usage
      )
      expect(LifetimeUsages::CheckThresholdsService).to have_received(:call).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage)
      )

      expect(result).to be_success
      expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "when lifetime_usage and progressive_billing are both disabled" do
    let(:premium_integrations) { ["salesforce"] }

    it "calculates and checks thresholds are not called" do
      result = service.call

      expect(LifetimeUsages::CalculateService).not_to have_received(:call!)
      expect(LifetimeUsages::CheckThresholdsService).not_to have_received(:call)

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
      result = service.call

      expect(LifetimeUsages::CalculateService).to have_received(:call!).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage),
        current_usage: mocked_current_usage
      )
      expect(LifetimeUsages::CheckThresholdsService).not_to have_received(:call)

      expect(result).to be_success
      expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "when progressive_billing_enabled is true" do
    let(:premium_integrations) { ["progressive_billing"] }

    it "calls both calculate and check thresholds services and deletes subscription_activity" do
      result = service.call

      expect(LifetimeUsages::CalculateService).to have_received(:call!).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage),
        current_usage: mocked_current_usage
      )
      expect(LifetimeUsages::CheckThresholdsService).to have_received(:call).with(
        lifetime_usage: subscription.lifetime_usage || an_instance_of(LifetimeUsage)
      )

      expect(result).to be_success
      expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "when lifetime_usage already exists" do
    let(:premium_integrations) { %w[progressive_billing] }

    it "does not create a new lifetime usage" do
      create(:lifetime_usage, subscription: subscription, organization: organization)
      expect { service.call }.not_to change(LifetimeUsage, :count)
    end
  end

  context "when subscription has alerts" do
    let(:premium_integrations) { [] }
    let(:alert) { create(:usage_amount_alert, recurring_threshold: 35, thresholds: [10, 20], previous_value: 4, code: "test", organization:, subscription_external_id: subscription.external_id) }

    before do
      alert
      allow(::UsageMonitoring::ProcessAlertService).to receive(:call)
    end

    it "processes the alerts" do
      service.call
      expect(::UsageMonitoring::ProcessAlertService).to have_received(:call).with(alert:, subscription:, current_metrics: mocked_current_usage)
      expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context "when alerting fail" do
      it "deletes subscription_activity before raising" do
        allow(::UsageMonitoring::ProcessAlertService).to receive(:call).and_raise(StandardError, "boom")
        expect { service.call }.to raise_error(StandardError, "boom")
        expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when progressive_billing fail" do
      let(:premium_integrations) { %w[lifetime_usage progressive_billing] }

      it "processes alert and then raise" do
        allow(LifetimeUsages::CheckThresholdsService).to receive(:call).and_raise(StandardError, "boom")
        expect { service.call }.to raise_error(StandardError, "boom")
        expect(::UsageMonitoring::ProcessAlertService).to have_received(:call).with(alert:, subscription:, current_metrics: mocked_current_usage)
        expect { subscription_activity.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
