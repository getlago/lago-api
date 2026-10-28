# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::Reports::Window do
  subject(:window) { described_class.new(from_datetime:, to_datetime:, timezone:) }

  let(:timezone) { "UTC" }
  let(:from_datetime) { Time.zone.parse("2026-08-24 09:20:00") }
  let(:to_datetime) { Time.zone.parse("2026-08-24 12:05:00") }

  it "reads short spans by the hour, widened to whole buckets" do
    expect(window.granularity).to eq("hour")
    expect(window.start_time).to eq(Time.zone.parse("2026-08-24 09:15:00"))
    expect(window.end_time).to eq(Time.zone.parse("2026-08-24 12:15:00"))
    expect(window.periods).to eq(
      ["09:00", "10:00", "11:00", "12:00"].map { |hour| Time.zone.parse("2026-08-24 #{hour}:00").to_i }
    )
    expect(window.errors).to eq({})
  end

  context "with an end on a bucket wall" do
    let(:to_datetime) { Time.zone.parse("2026-08-24 12:00:00") }

    it "keeps it" do
      expect(window.end_time).to eq(to_datetime)
      expect(window.periods.size).to eq(3)
    end
  end

  context "with a span longer than two days" do
    let(:to_datetime) { Time.zone.parse("2026-08-27 10:00:00") }

    it "reads by the day, from the bucket of the start rather than its midnight" do
      expect(window.granularity).to eq("day")
      expect(window.start_time).to eq(Time.zone.parse("2026-08-24 09:15:00"))
      expect(window.periods.first).to eq(Time.zone.parse("2026-08-24 00:00:00").to_i)
      expect(window.periods.size).to eq(4)
    end
  end

  context "with a timezone" do
    let(:timezone) { "Europe/Paris" }
    let(:from_datetime) { Time.zone.parse("2026-10-23 12:00:00") }
    let(:to_datetime) { Time.zone.parse("2026-10-27 12:00:00") }

    it "cuts the days on its midnights, across a DST change" do
      expect(window.periods.map { |period| Time.zone.at(period).in_time_zone(timezone).strftime("%F %H:%M") }).to eq(
        ["2026-10-23 00:00", "2026-10-24 00:00", "2026-10-25 00:00", "2026-10-26 00:00", "2026-10-27 00:00"]
      )
    end
  end

  context "without bounds" do
    let(:from_datetime) { nil }
    let(:to_datetime) { nil }

    it "reads the last 24 hours" do
      travel_to(Time.zone.parse("2026-08-24 12:00:00")) do
        expect(window.start_time).to eq(Time.zone.parse("2026-08-23 12:00:00"))
        expect(window.end_time).to eq(Time.zone.parse("2026-08-24 12:00:00"))
      end
    end
  end

  describe ".longest_from" do
    let(:timezone) { "Europe/Paris" }

    it "starts on the midnight 30 days before the end, in the timezone" do
      travel_to(Time.zone.parse("2026-08-24 12:00:00")) do
        from_datetime = described_class.longest_from(to_datetime: nil, timezone:)

        expect(from_datetime).to eq(Time.zone.parse("2026-07-24 22:00:00"))
        expect(described_class.new(from_datetime:, to_datetime: nil, timezone:).errors).to eq({})
      end
    end
  end

  context "with an inverted window" do
    let(:to_datetime) { from_datetime - 1.hour }

    it { expect(window.errors).to eq({from_datetime: ["invalid_window"]}) }
  end

  context "with a window longer than the maximum" do
    let(:to_datetime) { from_datetime + 32.days }

    it { expect(window.errors).to eq({to_datetime: ["window_too_long"]}) }
  end
end
