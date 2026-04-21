# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateSchedules::DatesService do
  subject(:date_service) do
    described_class.new(subscription_rate_schedule: srs, billing_at:, current_usage: false)
  end

  let(:started_at) { Time.zone.parse("2026-01-05") } # Monday
  let(:billing_anchor_date) { nil }
  let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "week", billing_interval_count: 1) }
  let(:srs) { create(:subscription_rate_schedule, rate_schedule:, started_at:, billing_anchor_date:) }

  # Weekly with count=1, started_at = Mon 2026-01-05:
  #   cycle 0: Jan 05 → Jan 11 23:59:59
  #   cycle 1: Jan 12 → Jan 18 23:59:59
  #   cycle 2: Jan 19 → Jan 25 23:59:59

  context "when billing_at is before started_at" do
    let(:billing_at) { Time.zone.parse("2026-01-04 10:00:00") }

    it "is cycle 0 from Jan 05 to Jan 11 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-11").end_of_day)
    end
  end

  context "when billing_at equals started_at" do
    let(:billing_at) { started_at }

    it "is cycle 0 from Jan 05 to Jan 11 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-11").end_of_day)
    end
  end

  context "when billing_at is mid first cycle" do
    let(:billing_at) { Time.zone.parse("2026-01-08 14:30:00") }

    it "is cycle 0 from Jan 05 to Jan 11 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-11").end_of_day)
    end
  end

  context "when billing_at is the last second of cycle 0" do
    let(:billing_at) { Time.zone.parse("2026-01-11 23:59:59") }

    it "is cycle 0 from Jan 05 to Jan 11 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-11").end_of_day)
    end
  end

  context "when billing_at is exactly the start of cycle 1" do
    let(:billing_at) { Time.zone.parse("2026-01-12") }

    it "is cycle 1 from Jan 12 to Jan 18 23:59:59" do
      expect(date_service.cycle_index).to eq(1)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-12"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-18").end_of_day)
    end
  end

  context "when billing_at is in the third cycle" do
    let(:billing_at) { Time.zone.parse("2026-01-20 12:00:00") }

    it "is cycle 2 from Jan 19 to Jan 25 23:59:59" do
      expect(date_service.cycle_index).to eq(2)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-19"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-25").end_of_day)
    end
  end

  context "when billing_at crosses a year boundary" do
    # started_at = Mon 2026-12-28
    #   cycle 0: Dec 28 2026 → Jan 03 2027 23:59:59
    #   cycle 1: Jan 04 2027 → Jan 10 2027 23:59:59
    let(:started_at) { Time.zone.parse("2026-12-28") }

    context "when billing_at is the last second of cycle 0" do
      let(:billing_at) { Time.zone.parse("2027-01-03 23:59:59") }

      it "is cycle 0 from Dec 28 2026 to Jan 03 2027 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-12-28"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2027-01-03").end_of_day)
      end
    end

    context "when billing_at is exactly Jan 04 2027 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2027-01-04") }

      it "is cycle 1 from Jan 04 2027 to Jan 10 2027 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2027-01-04"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2027-01-10").end_of_day)
      end
    end
  end

  context "with billing_interval_count of 2 (biweekly)" do
    # Cycles:
    #   cycle 0: Jan 05 → Jan 18 23:59:59
    #   cycle 1: Jan 19 → Feb 01 23:59:59
    #   cycle 2: Feb 02 → Feb 15 23:59:59
    let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "week", billing_interval_count: 2) }

    context "when billing_at is mid first biweek" do
      let(:billing_at) { Time.zone.parse("2026-01-12 10:00:00") }

      it "is cycle 0 from Jan 05 to Jan 18 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-18").end_of_day)
      end
    end

    context "when billing_at is the last second of cycle 0" do
      let(:billing_at) { Time.zone.parse("2026-01-18 23:59:59") }

      it "is cycle 0 from Jan 05 to Jan 18 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-18").end_of_day)
      end
    end

    context "when billing_at is exactly Jan 19 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2026-01-19") }

      it "is cycle 1 from Jan 19 to Feb 01 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-19"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-01").end_of_day)
      end
    end

    context "when billing_at is in the third biweekly cycle" do
      let(:billing_at) { Time.zone.parse("2026-02-10 10:00:00") }

      it "is cycle 2 from Feb 02 to Feb 15 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-02"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-15").end_of_day)
      end
    end
  end

  context "when the schedule has ended within the current cycle" do
    # cycle 0: Jan 05 → Jan 11 23:59:59, but ended_at = Jan 08 12:00
    let(:billing_at) { Time.zone.parse("2026-01-08") }

    before { srs.update!(ended_at: Time.zone.parse("2026-01-08 12:00:00")) }

    it "clamps to_datetime to ended_at (preserves real time)" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-08 12:00:00"))
    end
  end

  context "with billing_anchor_date wday=Thu, started Mon (anchor later in same week)" do
    # started_at = Mon Jan 5 2026, anchor.wday = 4 (Thu)
    # Cycles:
    #   cycle 0: Mon Jan 5  → Wed Jan 7  23:59:59  (partial, 3 days)
    #   cycle 1: Thu Jan 8  → Wed Jan 14 23:59:59
    #   cycle 2: Thu Jan 15 → Wed Jan 21 23:59:59
    let(:billing_anchor_date) { Date.new(2025, 12, 11) } # Thu

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2026-01-06") }

      it "is cycle 0 from Mon Jan 5 to Wed Jan 7 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-07").end_of_day)
      end
    end

    context "when billing_at is exactly Thu Jan 8 (cycle 1, first full)" do
      let(:billing_at) { Time.zone.parse("2026-01-08") }

      it "is cycle 1 from Thu Jan 8 to Wed Jan 14 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-08"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-14").end_of_day)
      end
    end

    context "when billing_at is in cycle 2" do
      let(:billing_at) { Time.zone.parse("2026-01-18") }

      it "is cycle 2 from Thu Jan 15 to Wed Jan 21 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-21").end_of_day)
      end
    end
  end

  context "with billing_anchor_date wday=Wed, started Fri (anchor earlier in week, wraps)" do
    # started_at = Fri Jan 9 2026, anchor.wday = 3 (Wed)
    # (3 - 5) % 7 = 5 → first = Fri + 5.days = Wed Jan 14
    # Cycles:
    #   cycle 0: Fri Jan 9  → Tue Jan 13 23:59:59  (partial, 5 days, wraps to next week)
    #   cycle 1: Wed Jan 14 → Tue Jan 20 23:59:59
    #   cycle 2: Wed Jan 21 → Tue Jan 27 23:59:59
    let(:started_at) { Time.zone.parse("2026-01-09") } # Friday
    let(:billing_anchor_date) { Date.new(2025, 12, 10) } # Wed

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2026-01-12") }

      it "is cycle 0 from Fri Jan 9 to Tue Jan 13 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-09"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-13").end_of_day)
      end
    end

    context "when billing_at is exactly Wed Jan 14 (cycle 1, first full)" do
      let(:billing_at) { Time.zone.parse("2026-01-14") }

      it "is cycle 1 from Wed Jan 14 to Tue Jan 20 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-14"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-20").end_of_day)
      end
    end
  end

  context "with billing_anchor_date wday matching started_at (aligned, no partial)" do
    # started_at = Mon Jan 5, anchor.wday = 1 (Mon) → aligned
    # Cycles (same as without anchor):
    #   cycle 0: Mon Jan 5  → Sun Jan 11 23:59:59
    #   cycle 1: Mon Jan 12 → Sun Jan 18 23:59:59
    let(:billing_anchor_date) { Date.new(2025, 12, 8) } # Mon

    context "when billing_at is mid first cycle" do
      let(:billing_at) { Time.zone.parse("2026-01-08") }

      it "is cycle 0 from Mon Jan 5 to Sun Jan 11 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-11").end_of_day)
      end
    end
  end

  context "with billing_anchor_date wday=Wed and biweekly (count=2)" do
    # started_at = Mon Jan 5, anchor.wday = 3 (Wed), count=2
    # first_full_cycle_start = Wed Jan 7
    # Cycles:
    #   cycle 0: Mon Jan 5  → Tue Jan 6  23:59:59  (partial, 2 days)
    #   cycle 1: Wed Jan 7  → Tue Jan 20 23:59:59  (14 days)
    #   cycle 2: Wed Jan 21 → Tue Feb 3  23:59:59
    let(:billing_anchor_date) { Date.new(2025, 12, 10) } # Wed
    let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "week", billing_interval_count: 2) }

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2026-01-06") }

      it "is cycle 0 from Mon Jan 5 to Tue Jan 6 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-06").end_of_day)
      end
    end

    context "when billing_at is exactly Wed Jan 7 (cycle 1, first full biweekly)" do
      let(:billing_at) { Time.zone.parse("2026-01-07") }

      it "is cycle 1 from Wed Jan 7 to Tue Jan 20 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-07"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-20").end_of_day)
      end
    end

    context "when billing_at is in cycle 2" do
      let(:billing_at) { Time.zone.parse("2026-01-25") }

      it "is cycle 2 from Wed Jan 21 to Tue Feb 3 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-21"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-03").end_of_day)
      end
    end
  end
end
