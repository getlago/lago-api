# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::ReplayDraftUsageJob do
  let(:contract) { create(:contract) }
  let(:published_at) { Time.zone.parse("2026-11-20 10:00:00") }

  before { allow(Contracts::ReplayDraftUsageService).to receive(:call!) }

  it "replays the usage received while the contract was a draft" do
    described_class.perform_now(contract, published_at)

    expect(Contracts::ReplayDraftUsageService).to have_received(:call!).with(contract:, published_at:)
  end
end
