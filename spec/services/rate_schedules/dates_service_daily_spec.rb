# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateSchedules::DatesService do
  subject(:date_service) do
    described_class.new(subscription_rate_schedule: srs, billing_at:, current_usage: false)
  end

  let(:started_at) { Time.zone.parse("2026-01-15") }
  let(:billing_anchor_date) { nil }
  let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "day", billing_interval_count: 1) }
  let(:srs) { create(:subscription_rate_schedule, rate_schedule:, started_at:, billing_anchor_date:) }

  # Daily with count=1, started_at = 2026-01-15:
  #   cycle 0: Jan 15 00:00 → Jan 15 23:59:59
  #   cycle 1: Jan 16 00:00 → Jan 16 23:59:59
  #   cycle 2: Jan 17 00:00 → Jan 17 23:59:59

  context "when billing_at is before started_at" do
    let(:billing_at) { Time.zone.parse("2026-01-14 23:59:59") }

    it "is cycle 0 from Jan 15 to Jan 15 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-15").end_of_day)
    end
  end

  context "when billing_at equals started_at" do
    let(:billing_at) { started_at }

    it "is cycle 0 from Jan 15 to Jan 15 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-15").end_of_day)
    end
  end

  context "when billing_at is mid first cycle" do
    let(:billing_at) { Time.zone.parse("2026-01-15 12:00:00") }

    it "is cycle 0 from Jan 15 to Jan 15 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-15").end_of_day)
    end
  end

  context "when billing_at is the last second of cycle 0" do
    let(:billing_at) { Time.zone.parse("2026-01-15 23:59:59") }

    it "is cycle 0 from Jan 15 to Jan 15 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-15").end_of_day)
    end
  end

  context "when billing_at is exactly the start of cycle 1" do
    let(:billing_at) { Time.zone.parse("2026-01-16") }

    it "is cycle 1 from Jan 16 to Jan 16 23:59:59" do
      expect(date_service.cycle_index).to eq(1)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-16"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-16").end_of_day)
    end
  end

  context "when billing_at is in the third cycle" do
    let(:billing_at) { Time.zone.parse("2026-01-17 14:00:00") }

    it "is cycle 2 from Jan 17 to Jan 17 23:59:59" do
      expect(date_service.cycle_index).to eq(2)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-17"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-17").end_of_day)
    end
  end

  context "when billing_at is 30 days after started_at" do
    let(:billing_at) { Time.zone.parse("2026-02-14") }

    it "is cycle 30 from Feb 14 to Feb 14 23:59:59" do
      expect(date_service.cycle_index).to eq(30)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-14"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
    end
  end

  context "when billing_at crosses a month boundary" do
    # started_at = Jan 31 2026
    #   cycle 0: Jan 31 → Jan 31 23:59:59
    #   cycle 1: Feb 01 → Feb 01 23:59:59
    let(:started_at) { Time.zone.parse("2026-01-31") }

    context "when billing_at is the last second of cycle 0" do
      let(:billing_at) { Time.zone.parse("2026-01-31 23:59:59") }

      it "is cycle 0 from Jan 31 to Jan 31 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-31"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-31").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 01 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2026-02-01") }

      it "is cycle 1 from Feb 01 to Feb 01 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-01"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-01").end_of_day)
      end
    end
  end

  context "when billing_at crosses a year boundary" do
    # started_at = Dec 31 2026
    #   cycle 0: Dec 31 2026 → Dec 31 2026 23:59:59
    #   cycle 1: Jan 01 2027 → Jan 01 2027 23:59:59
    let(:started_at) { Time.zone.parse("2026-12-31") }

    context "when billing_at is the last second of cycle 0" do
      let(:billing_at) { Time.zone.parse("2026-12-31 23:59:59") }

      it "is cycle 0 from Dec 31 2026 to Dec 31 2026 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-12-31"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-12-31").end_of_day)
      end
    end

    context "when billing_at is exactly Jan 01 2027 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2027-01-01") }

      it "is cycle 1 from Jan 01 2027 to Jan 01 2027 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2027-01-01"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2027-01-01").end_of_day)
      end
    end
  end

  context "with billing_interval_count of 7 (weekly via daily)" do
    # Cycles:
    #   cycle 0: Jan 15 → Jan 21 23:59:59
    #   cycle 1: Jan 22 → Jan 28 23:59:59
    #   cycle 2: Jan 29 → Feb 04 23:59:59
    let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "day", billing_interval_count: 7) }

    context "when billing_at is mid first cycle" do
      let(:billing_at) { Time.zone.parse("2026-01-18 12:00:00") }

      it "is cycle 0 from Jan 15 to Jan 21 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-21").end_of_day)
      end
    end

    context "when billing_at is the last second of cycle 0" do
      let(:billing_at) { Time.zone.parse("2026-01-21 23:59:59") }

      it "is cycle 0 from Jan 15 to Jan 21 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-21").end_of_day)
      end
    end

    context "when billing_at is exactly Jan 22 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2026-01-22") }

      it "is cycle 1 from Jan 22 to Jan 28 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-22"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-28").end_of_day)
      end
    end

    context "when billing_at is in the third cycle" do
      let(:billing_at) { Time.zone.parse("2026-01-30") }

      it "is cycle 2 from Jan 29 to Feb 04 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-29"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-04").end_of_day)
      end
    end
  end

  context "when the schedule has ended within the current cycle" do
    # cycle 0: Jan 15 00:00 → Jan 15 23:59:59, but ended_at = Jan 15 18:00
    let(:billing_at) { Time.zone.parse("2026-01-15 12:00:00") }

    before { srs.update!(ended_at: Time.zone.parse("2026-01-15 18:00:00")) }

    it "clamps to_datetime to ended_at (preserves real time)" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-15 18:00:00"))
    end
  end

  context "with billing_anchor_date set (anchor is ignored for daily)" do
    # Daily ignores anchor entirely — first_full_cycle_start always equals
    # started_at_beginning_of_day, so cycles are identical to the no-anchor case.
    let(:billing_anchor_date) { Date.new(2025, 12, 7) } # arbitrary, should have no effect

    context "when billing_at is mid first cycle" do
      let(:billing_at) { Time.zone.parse("2026-01-15 12:00:00") }

      it "is cycle 0 from Jan 15 to Jan 15 23:59:59 (anchor ignored)" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-15").end_of_day)
      end
    end

    context "when billing_at is exactly Jan 16 (cycle 1, no partial)" do
      let(:billing_at) { Time.zone.parse("2026-01-16") }

      it "is cycle 1 from Jan 16 to Jan 16 23:59:59 (anchor ignored)" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-16"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-16").end_of_day)
      end
    end
  end
end
