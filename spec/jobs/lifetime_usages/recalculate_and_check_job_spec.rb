# frozen_string_literal: true

require "rails_helper"

RSpec.describe LifetimeUsages::RecalculateAndCheckJob do
  let(:organization) { create(:organization, :premium, premium_integrations:) }
  let(:lifetime_usage) { create(:lifetime_usage, organization:) }

  let(:premium_integrations) { ["progressive_billing"] }

  it "delegates to the Calculate service" do
    allow(LifetimeUsages::CalculateService).to receive(:call!)
    allow(LifetimeUsages::CheckThresholdsService).to receive(:call!)
    described_class.perform_now(lifetime_usage)
    expect(LifetimeUsages::CalculateService).to have_received(:call!).with(lifetime_usage:, current_usage: nil)
    expect(LifetimeUsages::CheckThresholdsService).not_to have_received(:call!)
  end

  context "when premium", :premium do
    it "delegates to the RecalculateAndCheck service" do
      allow(LifetimeUsages::CalculateService).to receive(:call!)
      allow(LifetimeUsages::CheckThresholdsService).to receive(:call!)
      described_class.perform_now(lifetime_usage)
      expect(LifetimeUsages::CalculateService).to have_received(:call!).with(lifetime_usage:, current_usage: nil)
      expect(LifetimeUsages::CheckThresholdsService).to have_received(:call!).with(lifetime_usage:)
    end

    context "when progressive billing is disabled" do
      let(:premium_integrations) { [] }

      it "delegates to the RecalculateAndCheck service" do
        allow(LifetimeUsages::CalculateService).to receive(:call!)
        allow(LifetimeUsages::CheckThresholdsService).to receive(:call!)
        described_class.perform_now(lifetime_usage)
        expect(LifetimeUsages::CalculateService).to have_received(:call!).with(lifetime_usage:, current_usage: nil)
        expect(LifetimeUsages::CheckThresholdsService).not_to have_received(:call!)
      end
    end
  end
end
