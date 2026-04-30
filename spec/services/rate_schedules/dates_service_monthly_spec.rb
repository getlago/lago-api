# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateSchedules::DatesService do
  subject(:date_service) do
    described_class.new(subscription_rate_schedule: srs, billing_at:, current_usage: false)
  end

  let(:started_at) { Time.zone.parse("2026-01-15") }
  let(:billing_anchor_date) { nil }
  let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "month", billing_interval_count: 1) }
  let(:srs) { create(:subscription_rate_schedule, rate_schedule:, started_at:, billing_anchor_date:) }

  # Monthly with count=1, started_at = 2026-01-15:
  #   cycle 0: Jan 15 00:00 → Feb 14 23:59:59
  #   cycle 1: Feb 15 00:00 → Mar 14 23:59:59
  #   cycle 2: Mar 15 00:00 → Apr 14 23:59:59
  #   cycle 12: Jan 15 2027 00:00 → Feb 14 2027 23:59:59

  context "when billing_at is before started_at" do
    let(:billing_at) { Time.zone.parse("2026-01-10") }

    it "is cycle 0 from Jan 15 to Feb 14 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
    end
  end

  context "when billing_at equals started_at" do
    let(:billing_at) { started_at }

    it "is cycle 0 from Jan 15 to Feb 14 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
    end
  end

  context "when billing_at is mid first cycle" do
    let(:billing_at) { Time.zone.parse("2026-01-30") }

    it "is cycle 0 from Jan 15 to Feb 14 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
    end
  end

  context "when billing_at is the last second of cycle 0" do
    let(:billing_at) { Time.zone.parse("2026-02-14 23:59:59") }

    it "is cycle 0 from Jan 15 to Feb 14 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
    end
  end

  context "when billing_at is exactly the start of cycle 1" do
    let(:billing_at) { Time.zone.parse("2026-02-15") }

    it "is cycle 1 from Feb 15 to Mar 14 23:59:59" do
      expect(date_service.cycle_index).to eq(1)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-03-14").end_of_day)
    end
  end

  context "when billing_at is in the third cycle" do
    let(:billing_at) { Time.zone.parse("2026-03-16") }

    it "is cycle 2 from Mar 15 to Apr 14 23:59:59" do
      expect(date_service.cycle_index).to eq(2)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-04-14").end_of_day)
    end
  end

  context "when billing_at is exactly one year after started_at" do
    let(:billing_at) { Time.zone.parse("2027-01-15") }

    it "is cycle 12 from Jan 15 2027 to Feb 14 2027 23:59:59" do
      expect(date_service.cycle_index).to eq(12)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2027-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2027-02-14").end_of_day)
    end
  end

  context "when billing_at is one second before the 12th cycle starts" do
    let(:billing_at) { Time.zone.parse("2027-01-14 23:59:59") }

    it "is cycle 11 from Dec 15 2026 to Jan 14 2027 23:59:59" do
      expect(date_service.cycle_index).to eq(11)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-12-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2027-01-14").end_of_day)
    end
  end

  context "when started_at has a non-midnight time" do
    let(:started_at) { Time.zone.parse("2026-01-15 14:37:00") }
    let(:billing_at) { Time.zone.parse("2026-01-30") }

    it "anchors at midnight UTC, dropping the hour" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
    end
  end

  context "when started_at is on Jan 31 (month-end edge)" do
    # Rails clamps Jan 31 + 1.month to Feb 28. Cycles:
    #   cycle 0: Jan 31 → Feb 27 23:59:59
    #   cycle 1: Feb 28 → Mar 30 23:59:59
    #   cycle 2: Mar 31 → Apr 29 23:59:59
    #   cycle 3: Apr 30 → May 30 23:59:59
    let(:started_at) { Time.zone.parse("2026-01-31") }

    context "when billing_at is the last second before Feb 28" do
      let(:billing_at) { Time.zone.parse("2026-02-27 23:59:59") }

      it "is cycle 0 from Jan 31 to Feb 27 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-31"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-27").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 28 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2026-02-28") }

      it "is cycle 1 from Feb 28 to Mar 30 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-28"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-03-30").end_of_day)
      end
    end

    context "when billing_at is Mar 30 (still inside cycle 1)" do
      let(:billing_at) { Time.zone.parse("2026-03-30") }

      it "is cycle 1 from Feb 28 to Mar 30 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-28"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-03-30").end_of_day)
      end
    end

    context "when billing_at is exactly Mar 31 (cycle 2 start)" do
      let(:billing_at) { Time.zone.parse("2026-03-31") }

      it "is cycle 2 from Mar 31 to Apr 29 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-31"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-04-29").end_of_day)
      end
    end

    context "when billing_at is Apr 30 (cycle 3 start)" do
      let(:billing_at) { Time.zone.parse("2026-04-30") }

      it "is cycle 3 from Apr 30 to May 30 23:59:59" do
        expect(date_service.cycle_index).to eq(3)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-04-30"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-05-30").end_of_day)
      end
    end
  end

  context "when started_at is Feb 29 on a leap year" do
    # 2024 is leap, 2025/2026/2027 are not, 2028 is.
    #   cycle 11: Jan 29 2025 → Feb 27 2025 23:59:59
    #   cycle 12: Feb 28 2025 → Mar 28 2025 23:59:59
    #   cycle 48: Feb 29 2028 → Mar 28 2028 23:59:59
    let(:started_at) { Time.zone.parse("2024-02-29") }

    context "when billing_at is exactly Feb 28 2025 (cycle 12 start)" do
      let(:billing_at) { Time.zone.parse("2025-02-28") }

      it "is cycle 12 from Feb 28 2025 to Mar 28 2025 23:59:59" do
        expect(date_service.cycle_index).to eq(12)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2025-02-28"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2025-03-28").end_of_day)
      end
    end

    context "when billing_at is Feb 27 2025 (still inside cycle 11)" do
      let(:billing_at) { Time.zone.parse("2025-02-27") }

      it "is cycle 11 from Jan 29 2025 to Feb 27 2025 23:59:59" do
        expect(date_service.cycle_index).to eq(11)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2025-01-29"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2025-02-27").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 29 2028 (cycle 48 start)" do
      let(:billing_at) { Time.zone.parse("2028-02-29") }

      it "is cycle 48 from Feb 29 2028 to Mar 28 2028 23:59:59" do
        expect(date_service.cycle_index).to eq(48)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2028-02-29"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2028-03-28").end_of_day)
      end
    end
  end

  context "with billing_interval_count of 3 (quarterly)" do
    # Cycles:
    #   cycle 0: Jan 15 → Apr 14 23:59:59
    #   cycle 1: Apr 15 → Jul 14 23:59:59
    #   cycle 2: Jul 15 → Oct 14 23:59:59
    let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "month", billing_interval_count: 3) }

    context "when billing_at is mid first quarter" do
      let(:billing_at) { Time.zone.parse("2026-03-15") }

      it "is cycle 0 from Jan 15 to Apr 14 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-04-14").end_of_day)
      end
    end

    context "when billing_at is the last second of the first quarter" do
      let(:billing_at) { Time.zone.parse("2026-04-14 23:59:59") }

      it "is cycle 0 from Jan 15 to Apr 14 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-04-14").end_of_day)
      end
    end

    context "when billing_at is exactly Apr 15 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2026-04-15") }

      it "is cycle 1 from Apr 15 to Jul 14 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-04-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-07-14").end_of_day)
      end
    end

    context "when billing_at is exactly Jul 15 (cycle 2 start)" do
      let(:billing_at) { Time.zone.parse("2026-07-15") }

      it "is cycle 2 from Jul 15 to Oct 14 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-07-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-10-14").end_of_day)
      end
    end
  end

  context "when the schedule has ended within the current cycle" do
    # cycle 0: Jan 15 → Feb 14 23:59:59, but ended_at = Jan 25 12:00
    let(:billing_at) { Time.zone.parse("2026-01-30") }

    before { srs.update!(ended_at: Time.zone.parse("2026-01-25 12:00:00")) }

    it "clamps to_datetime to ended_at (preserves real time)" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-25 12:00:00"))
    end
  end

  context "when the schedule ended after the current cycle" do
    # cycle 0: Jan 15 → Feb 14 23:59:59, ended_at = Mar 10 (past the cycle)
    let(:billing_at) { Time.zone.parse("2026-01-30") }

    before { srs.update!(ended_at: Time.zone.parse("2026-03-10")) }

    it "does not clamp (next cycle start is earlier)" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
    end
  end

  context "with billing_anchor_date set to day 15, started Jan 5 (anchor in same month, after start)" do
    # Cycles:
    #   cycle 0: Jan 5 → Jan 14 23:59:59  (partial, 10 days)
    #   cycle 1: Jan 15 → Feb 14 23:59:59
    #   cycle 2: Feb 15 → Mar 14 23:59:59
    let(:started_at) { Time.zone.parse("2026-01-05") }
    let(:billing_anchor_date) { Date.new(2025, 12, 15) }

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2026-01-10") }

      it "is cycle 0 from Jan 5 to Jan 14 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-05"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-01-14").end_of_day)
      end
    end

    context "when billing_at is exactly Jan 15 (cycle 1, first full)" do
      let(:billing_at) { Time.zone.parse("2026-01-15") }

      it "is cycle 1 from Jan 15 to Feb 14 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
      end
    end

    context "when billing_at is in cycle 2" do
      let(:billing_at) { Time.zone.parse("2026-02-20") }

      it "is cycle 2 from Feb 15 to Mar 14 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-03-14").end_of_day)
      end
    end
  end

  context "with billing_anchor_date set to day 5, started Jan 20 (anchor already passed this month)" do
    # Anchor day 5 already passed in Jan when SRS started Jan 20, so first full cycle is in Feb.
    # Cycles:
    #   cycle 0: Jan 20 → Feb 4 23:59:59  (partial, 16 days)
    #   cycle 1: Feb 5 → Mar 4 23:59:59
    let(:started_at) { Time.zone.parse("2026-01-20") }
    let(:billing_anchor_date) { Date.new(2025, 12, 5) }

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2026-01-25") }

      it "is cycle 0 from Jan 20 to Feb 4 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-20"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-04").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 5 (cycle 1, first full)" do
      let(:billing_at) { Time.zone.parse("2026-02-05") }

      it "is cycle 1 from Feb 5 to Mar 4 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-05"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-03-04").end_of_day)
      end
    end
  end

  context "with billing_anchor_date matching started_at exactly (aligned, no partial)" do
    # Cycles (same as without anchor):
    #   cycle 0: Jan 15 → Feb 14 23:59:59  (full, no partial)
    #   cycle 1: Feb 15 → Mar 14 23:59:59
    let(:started_at) { Time.zone.parse("2026-01-15") }
    let(:billing_anchor_date) { Date.new(2025, 12, 15) }

    context "when billing_at is mid first cycle" do
      let(:billing_at) { Time.zone.parse("2026-01-30") }

      it "is cycle 0 from Jan 15 to Feb 14 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-14").end_of_day)
      end
    end
  end

  context "with billing_anchor_date day=31, started Feb 5 (clamping + restoration)" do
    # Anchor day 31 doesn't fit in Feb → first full cycle is Feb 28 (clamped).
    # Subsequent cycles re-project to canonical 31, restoring it where months allow.
    # Cycles:
    #   cycle 0: Feb 5 → Feb 27 23:59:59  (partial, 23 days)
    #   cycle 1: Feb 28 → Mar 30 23:59:59  (clamped from 31)
    #   cycle 2: Mar 31 → Apr 29 23:59:59  (restored to 31)
    #   cycle 3: Apr 30 → May 30 23:59:59  (clamped to 30, Apr has 30)
    #   cycle 4: May 31 → Jun 29 23:59:59  (restored to 31)
    let(:started_at) { Time.zone.parse("2026-02-05") }
    let(:billing_anchor_date) { Date.new(2025, 1, 31) }

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2026-02-15") }

      it "is cycle 0 from Feb 5 to Feb 27 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-05"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-27").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 28 (cycle 1, clamped)" do
      let(:billing_at) { Time.zone.parse("2026-02-28") }

      it "is cycle 1 from Feb 28 to Mar 30 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-02-28"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-03-30").end_of_day)
      end
    end

    context "when billing_at is exactly Mar 31 (cycle 2, restored to 31)" do
      let(:billing_at) { Time.zone.parse("2026-03-31") }

      it "is cycle 2 from Mar 31 to Apr 29 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-31"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-04-29").end_of_day)
      end
    end

    context "when billing_at is exactly Apr 30 (cycle 3, clamped to 30)" do
      let(:billing_at) { Time.zone.parse("2026-04-30") }

      it "is cycle 3 from Apr 30 to May 30 23:59:59" do
        expect(date_service.cycle_index).to eq(3)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-04-30"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-05-30").end_of_day)
      end
    end

    context "when billing_at is exactly May 31 (cycle 4, restored to 31)" do
      let(:billing_at) { Time.zone.parse("2026-05-31") }

      it "is cycle 4 from May 31 to Jun 29 23:59:59" do
        expect(date_service.cycle_index).to eq(4)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-05-31"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-06-29").end_of_day)
      end
    end
  end

  context "with billing_anchor_date and quarterly (count=3)" do
    # Cycles (quarterly, anchor day 15, started Jan 5):
    #   cycle 0: Jan 5 → Jan 14 23:59:59  (partial, 10 days)
    #   cycle 1: Jan 15 → Apr 14 23:59:59
    #   cycle 2: Apr 15 → Jul 14 23:59:59
    #   cycle 3: Jul 15 → Oct 14 23:59:59
    let(:started_at) { Time.zone.parse("2026-01-05") }
    let(:billing_anchor_date) { Date.new(2025, 12, 15) }
    let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "month", billing_interval_count: 3) }

    context "when billing_at is in cycle 1 (first full quarter)" do
      let(:billing_at) { Time.zone.parse("2026-03-01") }

      it "is cycle 1 from Jan 15 to Apr 14 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-04-14").end_of_day)
      end
    end

    context "when billing_at is exactly Apr 15 (cycle 2 start)" do
      let(:billing_at) { Time.zone.parse("2026-04-15") }

      it "is cycle 2 from Apr 15 to Jul 14 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-04-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-07-14").end_of_day)
      end
    end
  end
end
