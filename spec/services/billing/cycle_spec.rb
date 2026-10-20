# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Cycle do
  subject(:cycle) { described_class.new(index: 0, started_at:, ended_at:, phase: Billing::Phase.default, calendar:) }

  let(:calendar) do
    Billing::Calendar.new(anchor_date: Date.new(2026, 1, 1), interval: Billing::Interval.new(count: 1, unit: :month), timezone: "UTC")
  end
  let(:started_at) { Time.utc(2026, 1, 1) }
  let(:ended_at) { Time.utc(2026, 2, 1) }

  describe "#closed_early?" do
    it "is false for a cycle its calendar closes" do
      expect(cycle).not_to be_closed_early
    end

    context "when the contract ends inside it" do
      let(:ended_at) { Time.utc(2026, 1, 20, 14) }

      it { is_expected.to be_closed_early }
    end

    # Only the end matters: a cycle opening after its anchor still runs to the boundary.
    context "when it starts after its anchor" do
      let(:started_at) { Time.utc(2026, 1, 15) }

      it { is_expected.not_to be_closed_early }
    end
  end
end
