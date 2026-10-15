# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Segments do
  # Only effective_from is read, so the cases below stay free of the catalog.
  def rate(code, effective_from)
    Struct.new(:code, :effective_from).new(code, effective_from)
  end

  def windows(segments)
    segments.map { |segment| [segment.started_at.to_date.to_s, segment.ended_at.to_date.to_s, segment.rate&.code] }
  end

  # The window is anything answering started_at/ended_at — a Cycle in production.
  def window_of(from, to) = Struct.new(:started_at, :ended_at).new(from, to)

  let(:window) { window_of(Time.utc(2026, 9, 10), Time.utc(2026, 10, 10)) }

  describe ".within" do
    it "leaves a window whole when no rate changes inside it" do
      segments = described_class.within(window, rates: [rate("v1", Time.utc(2026, 1, 1))])

      expect(windows(segments)).to eq([["2026-09-10", "2026-10-10", "v1"]])
    end

    # QA plan R3b — a mid-window change splits the cycle into two priced windows.
    it "cuts the window where a rate takes effect inside it" do
      rates = [rate("v1", Time.utc(2026, 1, 1)), rate("v2", Time.utc(2026, 9, 25))]

      expect(windows(described_class.within(window, rates:))).to eq(
        [
          ["2026-09-10", "2026-09-25", "v1"],
          ["2026-09-25", "2026-10-10", "v2"]
        ]
      )
    end

    it "cuts once per change" do
      rates = [
        rate("v1", Time.utc(2026, 1, 1)),
        rate("v2", Time.utc(2026, 9, 20)),
        rate("v3", Time.utc(2026, 9, 30))
      ]

      expect(windows(described_class.within(window, rates:))).to eq(
        [
          ["2026-09-10", "2026-09-20", "v1"],
          ["2026-09-20", "2026-09-30", "v2"],
          ["2026-09-30", "2026-10-10", "v3"]
        ]
      )
    end

    # QA plan R3a — "effective date ON a boundary (no split)". The change is simply the
    # rate in force from the first instant, so there is nothing to cut.
    it "does not cut for a change landing on the window's start" do
      rates = [rate("v1", Time.utc(2026, 1, 1)), rate("v2", Time.utc(2026, 9, 10))]

      expect(windows(described_class.within(window, rates:))).to eq([["2026-09-10", "2026-10-10", "v2"]])
    end

    it "does not cut for a change landing on the window's end" do
      rates = [rate("v1", Time.utc(2026, 1, 1)), rate("v2", Time.utc(2026, 10, 10))]

      expect(windows(described_class.within(window, rates:))).to eq([["2026-09-10", "2026-10-10", "v1"]])
    end

    it "keeps the whole window unpriced while no rate is in force" do
      segments = described_class.within(window, rates: [rate("v1", Time.utc(2027, 1, 1))])

      expect(windows(segments)).to eq([["2026-09-10", "2026-10-10", nil]])
    end

    it "keeps the unpriced period before the first rate takes effect" do
      segments = described_class.within(window, rates: [rate("v1", Time.utc(2026, 9, 25))])

      expect(windows(segments)).to eq([
        ["2026-09-10", "2026-09-25", nil],
        ["2026-09-25", "2026-10-10", "v1"]
      ])
    end

    it "keeps the window unpriced when the first rate starts at its exclusive end" do
      segments = described_class.within(window, rates: [rate("v1", window.ended_at)])

      expect(windows(segments)).to eq([["2026-09-10", "2026-10-10", nil]])
    end

    it "does not require the rates to be ordered" do
      rates = [rate("v2", Time.utc(2026, 9, 25)), rate("v1", Time.utc(2026, 1, 1))]

      expect(windows(described_class.within(window, rates:)).map(&:last)).to eq(%w[v1 v2])
    end

    it "keeps the whole window unpriced when there are no rates" do
      expect(windows(described_class.within(window, rates: []))).to eq([["2026-09-10", "2026-10-10", nil]])
    end

    it "covers the whole window without gaps or overlap, including the unpriced period" do
      rates = [
        rate("v1", Time.utc(2026, 9, 15)),
        rate("v2", Time.utc(2026, 9, 20)),
        rate("v3", Time.utc(2026, 9, 30))
      ]
      segments = described_class.within(window, rates:)

      expect(segments.first.started_at).to eq(window.started_at)
      expect(segments.last.ended_at).to eq(window.ended_at)
      expect(segments.each_cons(2).all? { |before, after| before.ended_at == after.started_at }).to be(true)
    end
  end
end
