# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessLifetimeUsageAlertService, :premium do
  subject(:service) { described_class.new(alert:) }

  let(:organization) { create(:organization, premium_integrations:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let!(:charge) { create(:standard_charge, billable_metric:, plan: subscription.plan) }
  let(:alert) do
    create(:billable_metric_lifetime_usage_units_alert,
      billable_metric:, organization:, subscription_external_id: subscription.external_id)
  end
  let(:mocked_usage) { double("usage") } # rubocop:disable RSpec/VerifiedDoubles

  before do
    allow(::Invoices::CustomerUsageService).to receive(:call)
      .and_return(double(success?: true, usage: mocked_usage)) # rubocop:disable RSpec/VerifiedDoubles
    allow(::UsageMonitoring::ProcessAlertService).to receive(:call)
  end

  context "when lifetime_usage is enabled" do
    let(:premium_integrations) { %w[lifetime_usage] }

    it "calls CustomerUsageService and processes the alert" do
      service.call

      expect(::Invoices::CustomerUsageService).to have_received(:call).with(
        customer: an_object_having_attributes(id: subscription.customer_id),
        subscription: an_object_having_attributes(id: subscription.id),
        apply_taxes: false,
        with_cache: true,
        usage_filters: an_instance_of(UsageFilters)
      )
      expect(::UsageMonitoring::ProcessAlertService).to have_received(:call)
        .with(alert:, subscription: an_object_having_attributes(id: subscription.id), current_metrics: mocked_usage)
    end
  end

  context "when lifetime_usage is not enabled" do
    let(:premium_integrations) { [] }

    it "does not process the alert" do
      service.call

      expect(::Invoices::CustomerUsageService).not_to have_received(:call)
      expect(::UsageMonitoring::ProcessAlertService).not_to have_received(:call)
    end
  end

  context "when subscription is not active" do
    let(:premium_integrations) { %w[lifetime_usage] }
    let(:subscription) { create(:subscription, :terminated, customer:, organization:) }

    it "does not process the alert" do
      service.call

      expect(::Invoices::CustomerUsageService).not_to have_received(:call)
      expect(::UsageMonitoring::ProcessAlertService).not_to have_received(:call)
    end
  end

  context "when there are no matching charges" do
    let(:premium_integrations) { %w[lifetime_usage] }

    before { charge.destroy! }

    it "does not call CustomerUsageService or process the alert" do
      service.call

      expect(::Invoices::CustomerUsageService).not_to have_received(:call)
      expect(::UsageMonitoring::ProcessAlertService).not_to have_received(:call)
    end
  end

  context "when CustomerUsageService fails" do
    let(:premium_integrations) { %w[lifetime_usage] }

    before do
      allow(::Invoices::CustomerUsageService).to receive(:call)
        .and_return(double(success?: false)) # rubocop:disable RSpec/VerifiedDoubles
    end

    it "does not process the alert" do
      service.call

      expect(::UsageMonitoring::ProcessAlertService).not_to have_received(:call)
    end
  end
end
