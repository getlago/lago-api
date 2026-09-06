# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RateTimeline do
  # A rate is duck-typed: the timeline reads `effective_from` and nothing else.
  catalog_rate = Struct.new(:code, :effective_from, keyword_init: true)

  let(:june) { Time.utc(2024, 6, 1)...Time.utc(2024, 7, 1) }
  let(:first) { catalog_rate.new(code: "first", effective_from: Time.utc(2024, 1, 1)) }
  let(:second) { catalog_rate.new(code: "second", effective_from: Time.utc(2024, 6, 10)) }
  let(:third) { catalog_rate.new(code: "third", effective_from: Time.utc(2024, 6, 20)) }

  describe "#empty?" do
    it "is true without rates" do
      expect(described_class.new([])).to be_empty
    end

    it "is false with rates" do
      expect(described_class.new([first])).not_to be_empty
    end
  end

  describe "#earliest" do
    it "is nil without rates" do
      expect(described_class.new([]).earliest).to be_nil
    end

    it "is the first rate by effective_from, whatever order it was given in" do
      expect(described_class.new([third, first, second]).earliest).to eq(first)
    end

    it "resolves a tie to the first rate given" do
      other = catalog_rate.new(code: "other", effective_from: first.effective_from)

      expect(described_class.new([first, other]).earliest).to eq(first)
    end
  end

  describe "#at" do
    subject(:timeline) { described_class.new([third, first, second]) }

    it "is nil before every rate" do
      expect(timeline.at(Time.utc(2023, 12, 31))).to be_nil
    end

    it "is the rate effective exactly at the timestamp" do
      expect(timeline.at(Time.utc(2024, 6, 10))).to eq(second)
    end

    it "is the latest rate effective at or before the timestamp" do
      expect(timeline.at(Time.utc(2024, 6, 15))).to eq(second)
    end

    it "is the last rate for a timestamp after all of them" do
      expect(timeline.at(Time.utc(2030, 1, 1))).to eq(third)
    end

    it "is the earliest rate at its own effective_from" do
      expect(timeline.at(Time.utc(2024, 1, 1))).to eq(first)
    end

    it "is nil one second before the earliest rate" do
      expect(timeline.at(Time.utc(2024, 1, 1) - 1.second)).to be_nil
    end

    it "resolves a tie to the last rate given" do
      other = catalog_rate.new(code: "other", effective_from: second.effective_from)

      expect(described_class.new([second, other]).at(Time.utc(2024, 6, 15))).to eq(other)
    end
  end

  describe "#segments_within" do
    it "returns one segment spanning the window when no rate changes inside it" do
      segments = described_class.new([first]).segments_within(june)

      expect(segments).to eq([Billing::Segment.new(started_at: june.begin, ended_at: june.end, rate: first)])
    end

    it "cuts the window at a rate change inside it" do
      segments = described_class.new([first, second]).segments_within(june)

      expect(segments).to eq(
        [
          Billing::Segment.new(started_at: june.begin, ended_at: second.effective_from, rate: first),
          Billing::Segment.new(started_at: second.effective_from, ended_at: june.end, rate: second)
        ]
      )
    end

    it "cuts the window at every rate change inside it" do
      segments = described_class.new([first, second, third]).segments_within(june)

      expect(segments).to eq(
        [
          Billing::Segment.new(started_at: june.begin, ended_at: second.effective_from, rate: first),
          Billing::Segment.new(started_at: second.effective_from, ended_at: third.effective_from, rate: second),
          Billing::Segment.new(started_at: third.effective_from, ended_at: june.end, rate: third)
        ]
      )
    end

    it "returns contiguous segments covering the whole window" do
      segments = described_class.new([first, second, third]).segments_within(june)
      edges = [segments.first.started_at, *segments.each_cons(2).map { |before, after| after.started_at == before.ended_at }, segments.last.ended_at]

      expect(edges).to eq([june.begin, true, true, june.end])
    end

    it "does not cut on a change landing exactly on the window start" do
      opening = catalog_rate.new(code: "opening", effective_from: june.begin)
      segments = described_class.new([first, opening]).segments_within(june)

      expect(segments).to eq([Billing::Segment.new(started_at: june.begin, ended_at: june.end, rate: opening)])
    end

    it "does not cut on a change landing exactly on the window end" do
      closing = catalog_rate.new(code: "closing", effective_from: june.end)
      segments = described_class.new([first, closing]).segments_within(june)

      expect(segments).to eq([Billing::Segment.new(started_at: june.begin, ended_at: june.end, rate: first)])
    end

    it "collapses duplicate effective dates into a single cut" do
      duplicate = catalog_rate.new(code: "duplicate", effective_from: second.effective_from)
      segments = described_class.new([first, second, duplicate]).segments_within(june)

      expect(segments).to eq(
        [
          Billing::Segment.new(started_at: june.begin, ended_at: second.effective_from, rate: first),
          Billing::Segment.new(started_at: second.effective_from, ended_at: june.end, rate: duplicate)
        ]
      )
    end

    it "returns nothing for a window entirely before every rate" do
      may = Time.utc(2023, 5, 1)...Time.utc(2023, 6, 1)

      expect(described_class.new([first, second]).segments_within(may)).to eq([])
    end

    it "returns nothing when the timeline is empty" do
      expect(described_class.new([]).segments_within(june)).to eq([])
    end

    it "drops the leading piece that no rate prices yet" do
      window = Time.utc(2024, 6, 1)...Time.utc(2024, 7, 1)
      segments = described_class.new([second]).segments_within(window)

      expect(segments).to eq([Billing::Segment.new(started_at: second.effective_from, ended_at: window.end, rate: second)])
    end

    it "never returns a segment carrying a nil rate" do
      segments = described_class.new([second, third]).segments_within(june)

      expect(segments.map(&:rate)).to eq([second, third])
    end

    it "never returns an empty segment" do
      duplicate = catalog_rate.new(code: "duplicate", effective_from: second.effective_from)
      segments = described_class.new([first, second, duplicate, third]).segments_within(june)

      expect(segments.map { |segment| segment.ended_at > segment.started_at }).to eq([true, true, true])
    end

    it "ignores rate changes outside the window" do
      april = Time.utc(2024, 4, 1)...Time.utc(2024, 5, 1)

      expect(described_class.new([first, second, third]).segments_within(april))
        .to eq([Billing::Segment.new(started_at: april.begin, ended_at: april.end, rate: first)])
    end

    it "handles rates given out of order" do
      segments = described_class.new([third, second, first]).segments_within(june)

      expect(segments.map(&:rate)).to eq([first, second, third])
    end
  end
end
