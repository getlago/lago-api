# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::EmitFixedChargeEventsJob, type: :job do
  let(:subscriptions) { [create(:subscription)] }
  let(:timestamp) { Time.current.to_i }
  let(:emit_fixed_charge_events_service) do
    Subscriptions::EmitFixedChargeEventsService
  end

  before do
    allow(emit_fixed_charge_events_service).to receive(:call!)
  end

  it "calls Subscriptions::EmitFixedChargeEventsService" do
    described_class.perform_now(subscriptions:, timestamp:)

    expect(emit_fixed_charge_events_service)
      .to have_received(:call!)
      .with(
        subscriptions:,
        timestamp: Time.zone.at(timestamp)
      )
      .once
  end

  it "uses current timestamp when not provided" do
    freeze_time do
      described_class.perform_now(subscriptions:)

      expect(emit_fixed_charge_events_service)
        .to have_received(:call!)
        .with(
          subscriptions:,
          timestamp: Time.current
        )
        .once
    end
  end
end
