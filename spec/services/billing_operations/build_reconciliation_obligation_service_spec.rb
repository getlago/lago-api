# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::BuildReconciliationObligationService do
  subject(:result) { described_class.call(schedule:, target_cycle_started_at:) }

  let(:target_cycle_started_at) { Time.utc(2026, 11, 1) }
  let(:boundary) { Time.utc(2026, 11, 15) }
  let(:cycle_ended_at) { Time.utc(2026, 12, 1) }
  let(:cycle) do
    Billing::Cycle.new(index: 0, started_at: target_cycle_started_at, ended_at: cycle_ended_at, phase: Billing::Phase.default, calendar: nil)
  end
  let(:terms) { Billing::Terms.new(timing: :advance, prorated: true, billing_scope: :segment) }
  let(:first_segment) do
    Billing::Segments::Segment.new(started_at: target_cycle_started_at, ended_at: boundary, rate: instance_double(RateCardRate))
  end
  let(:second_segment) do
    Billing::Segments::Segment.new(started_at: boundary, ended_at: cycle_ended_at, rate: instance_double(RateCardRate))
  end
  let(:first_obligation) do
    Billing::Obligation.new(cycle:, segments: [first_segment].freeze, billing_at: target_cycle_started_at, terms:)
  end
  let(:second_obligation) do
    first_obligation.with(segments: [second_segment].freeze, billing_at: boundary)
  end
  let(:obligations) { [first_obligation, second_obligation].freeze }
  let(:schedule) { instance_double(Billing::RateCards::Schedule) }

  before do
    allow(schedule).to receive(:obligations_for_cycle).with(target_cycle_started_at).and_return(obligations)
  end

  it "returns the entire cycle with the first obligation's metadata and the original segments in schedule order" do
    expect(result).to be_success
    expect(result.obligation).to eq(first_obligation.with(segments: [first_segment, second_segment]))
    expect(result.obligation.segments).to match([equal(first_segment), equal(second_segment)])
    expect(first_obligation.segments).to eq([first_segment])
    expect(second_obligation.segments).to eq([second_segment])
  end

  context "when the schedule has no obligations for the target cycle" do
    let(:obligations) { [] }

    it "succeeds without an obligation" do
      expect(result).to be_success
      expect(result.obligation).to be_nil
    end
  end
end
