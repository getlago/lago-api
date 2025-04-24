# frozen_string_literal: true

require "rails_helper"

RSpec.describe LifetimeUsages::RecalculateAndCheckJob, type: :job do
  let(:lifetime_usage) { create(:lifetime_usage) }

  it "delegates to the RecalculateAndCheck service" do
    allow(LifetimeUsages::CalculateService).to receive(:call!)
    allow(LifetimeUsages::CheckThresholdsService).to receive(:call)
    described_class.perform_now(lifetime_usage)
    expect(LifetimeUsages::CalculateService).to have_received(:call!).with(lifetime_usage:)
    expect(LifetimeUsages::CheckThresholdsService).to have_received(:call).with(lifetime_usage:)
  end
end
