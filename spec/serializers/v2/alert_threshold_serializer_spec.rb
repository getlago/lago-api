# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::AlertThresholdSerializer do
  subject(:payload) { described_class.new(threshold).serialize }

  let(:threshold) do
    build_stubbed(
      :contract_alert_threshold,
      alert: build_stubbed(:contract_alert, contract_external_id: "ctr_123"),
      code: "high",
      value: 2_000_000,
      recurring: false,
      notify_on: %w[triggered resolved]
    )
  end

  it "serializes the threshold" do
    expect(payload).to eq(
      code: "high",
      value: BigDecimal("2000000"),
      recurring: false,
      notify_on: %w[triggered resolved]
    )
  end
end
