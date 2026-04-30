# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateSchedules::DatesService do
  subject(:date_service) do
    described_class.new(subscription_rate_schedule: srs, billing_at:, current_usage: false)
  end

  let(:started_at) { Time.zone.parse("2026-03-15") }
  let(:billing_anchor_date) { nil }
  let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "year", billing_interval_count: 1) }
  let(:srs) { create(:subscription_rate_schedule, rate_schedule:, started_at:, billing_anchor_date:) }

  # Yearly with count=1, started_at = 2026-03-15:
  #   cycle 0: Mar 15 2026 → Mar 14 2027 23:59:59
  #   cycle 1: Mar 15 2027 → Mar 14 2028 23:59:59
  #   cycle 2: Mar 15 2028 → Mar 14 2029 23:59:59

  context "when billing_at is before started_at" do
    let(:billing_at) { Time.zone.parse("2026-01-01") }

    it "is cycle 0 from Mar 15 2026 to Mar 14 2027 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2027-03-14").end_of_day)
    end
  end

  context "when billing_at equals started_at" do
    let(:billing_at) { started_at }

    it "is cycle 0 from Mar 15 2026 to Mar 14 2027 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2027-03-14").end_of_day)
    end
  end

  context "when billing_at is mid first cycle" do
    let(:billing_at) { Time.zone.parse("2026-09-01") }

    it "is cycle 0 from Mar 15 2026 to Mar 14 2027 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2027-03-14").end_of_day)
    end
  end

  context "when billing_at is the last second of cycle 0" do
    let(:billing_at) { Time.zone.parse("2027-03-14 23:59:59") }

    it "is cycle 0 from Mar 15 2026 to Mar 14 2027 23:59:59" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2027-03-14").end_of_day)
    end
  end

  context "when billing_at is exactly the start of cycle 1" do
    let(:billing_at) { Time.zone.parse("2027-03-15") }

    it "is cycle 1 from Mar 15 2027 to Mar 14 2028 23:59:59" do
      expect(date_service.cycle_index).to eq(1)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2027-03-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2028-03-14").end_of_day)
    end
  end

  context "when billing_at is in the third cycle" do
    let(:billing_at) { Time.zone.parse("2028-06-01") }

    it "is cycle 2 from Mar 15 2028 to Mar 14 2029 23:59:59" do
      expect(date_service.cycle_index).to eq(2)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2028-03-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2029-03-14").end_of_day)
    end
  end

  context "when started_at is Feb 29 on a leap year" do
    # 2024 is leap, 2025/2026/2027 are not, 2028 is.
    #   cycle 0: Feb 29 2024 → Feb 27 2025 23:59:59
    #   cycle 1: Feb 28 2025 → Feb 27 2026 23:59:59
    #   cycle 4: Feb 29 2028 → Feb 27 2029 23:59:59
    let(:started_at) { Time.zone.parse("2024-02-29") }

    context "when billing_at is Feb 27 2025 (still inside cycle 0)" do
      let(:billing_at) { Time.zone.parse("2025-02-27") }

      it "is cycle 0 from Feb 29 2024 to Feb 27 2025 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2024-02-29"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2025-02-27").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 28 2025 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2025-02-28") }

      it "is cycle 1 from Feb 28 2025 to Feb 27 2026 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2025-02-28"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-27").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 29 2028 (cycle 4 start)" do
      let(:billing_at) { Time.zone.parse("2028-02-29") }

      it "is cycle 4 from Feb 29 2028 to Feb 27 2029 23:59:59" do
        expect(date_service.cycle_index).to eq(4)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2028-02-29"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2029-02-27").end_of_day)
      end
    end
  end

  context "with billing_interval_count of 2 (biennial)" do
    # Cycles:
    #   cycle 0: Mar 15 2026 → Mar 14 2028 23:59:59
    #   cycle 1: Mar 15 2028 → Mar 14 2030 23:59:59
    #   cycle 2: Mar 15 2030 → Mar 14 2032 23:59:59
    let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "year", billing_interval_count: 2) }

    context "when billing_at is mid first biennial" do
      let(:billing_at) { Time.zone.parse("2027-06-01") }

      it "is cycle 0 from Mar 15 2026 to Mar 14 2028 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2028-03-14").end_of_day)
      end
    end

    context "when billing_at is the last second of cycle 0" do
      let(:billing_at) { Time.zone.parse("2028-03-14 23:59:59") }

      it "is cycle 0 from Mar 15 2026 to Mar 14 2028 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2028-03-14").end_of_day)
      end
    end

    context "when billing_at is exactly Mar 15 2028 (cycle 1 start)" do
      let(:billing_at) { Time.zone.parse("2028-03-15") }

      it "is cycle 1 from Mar 15 2028 to Mar 14 2030 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2028-03-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2030-03-14").end_of_day)
      end
    end

    context "when billing_at is in the third biennial cycle" do
      let(:billing_at) { Time.zone.parse("2030-06-01") }

      it "is cycle 2 from Mar 15 2030 to Mar 14 2032 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2030-03-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2032-03-14").end_of_day)
      end
    end
  end

  context "when the schedule has ended within the current cycle" do
    # cycle 0: Mar 15 2026 → Mar 14 2027 23:59:59, but ended_at = Aug 01 2026
    let(:billing_at) { Time.zone.parse("2026-09-01") }

    before { srs.update!(ended_at: Time.zone.parse("2026-08-01")) }

    it "clamps to_datetime to ended_at (preserves real time)" do
      expect(date_service.cycle_index).to eq(0)
      expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
      expect(date_service.to_datetime).to eq(Time.zone.parse("2026-08-01"))
    end
  end

  context "with billing_anchor_date Jun 15, started Mar 15 (anchor later in same year)" do
    # Cycles:
    #   cycle 0: Mar 15 2026 → Jun 14 2026 23:59:59  (partial, ~3 months)
    #   cycle 1: Jun 15 2026 → Jun 14 2027 23:59:59
    #   cycle 2: Jun 15 2027 → Jun 14 2028 23:59:59
    let(:billing_anchor_date) { Date.new(2025, 6, 15) }

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2026-04-01") }

      it "is cycle 0 from Mar 15 2026 to Jun 14 2026 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-06-14").end_of_day)
      end
    end

    context "when billing_at is exactly Jun 15 2026 (cycle 1, first full)" do
      let(:billing_at) { Time.zone.parse("2026-06-15") }

      it "is cycle 1 from Jun 15 2026 to Jun 14 2027 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-06-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2027-06-14").end_of_day)
      end
    end

    context "when billing_at is in cycle 2" do
      let(:billing_at) { Time.zone.parse("2027-09-01") }

      it "is cycle 2 from Jun 15 2027 to Jun 14 2028 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2027-06-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2028-06-14").end_of_day)
      end
    end
  end

  context "with billing_anchor_date Jan 15, started Mar 15 (anchor before started_at, wraps to next year)" do
    # Cycles:
    #   cycle 0: Mar 15 2026 → Jan 14 2027 23:59:59  (partial, ~10 months)
    #   cycle 1: Jan 15 2027 → Jan 14 2028 23:59:59
    let(:billing_anchor_date) { Date.new(2025, 1, 15) }

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2026-09-01") }

      it "is cycle 0 from Mar 15 2026 to Jan 14 2027 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2027-01-14").end_of_day)
      end
    end

    context "when billing_at is exactly Jan 15 2027 (cycle 1, first full)" do
      let(:billing_at) { Time.zone.parse("2027-01-15") }

      it "is cycle 1 from Jan 15 2027 to Jan 14 2028 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2027-01-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2028-01-14").end_of_day)
      end
    end
  end

  context "with billing_anchor_date matching started_at exactly (aligned, no partial)" do
    # Cycles (same as without anchor):
    #   cycle 0: Mar 15 2026 → Mar 14 2027 23:59:59  (full, no partial)
    let(:billing_anchor_date) { Date.new(2025, 3, 15) }

    context "when billing_at is mid first cycle" do
      let(:billing_at) { Time.zone.parse("2026-09-01") }

      it "is cycle 0 from Mar 15 2026 to Mar 14 2027 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-03-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2027-03-14").end_of_day)
      end
    end
  end

  context "with billing_anchor_date Feb 29, started Mar 1 2024 (clamping + restoration on leap)" do
    # Anchor Feb 29 (leap), started_at = Mar 1 2024.
    # First anchor occurrence after started_at is Feb 28 2025 (clamped, non-leap).
    # Cycles:
    #   cycle 0: Mar 1 2024 → Feb 27 2025 23:59:59  (partial, ~11 months)
    #   cycle 1: Feb 28 2025 → Feb 27 2026 23:59:59  (clamped to 28)
    #   cycle 2: Feb 28 2026 → Feb 27 2027 23:59:59  (re-projected, still clamped)
    #   cycle 3: Feb 28 2027 → Feb 28 2028 23:59:59  (re-projected, ends day before Feb 29 2028)
    #   cycle 4: Feb 29 2028 → Feb 27 2029 23:59:59  (RESTORED to 29 in leap year!)
    let(:started_at) { Time.zone.parse("2024-03-01") }
    let(:billing_anchor_date) { Date.new(2024, 2, 29) }

    context "when billing_at is in cycle 0 (the partial)" do
      let(:billing_at) { Time.zone.parse("2024-09-01") }

      it "is cycle 0 from Mar 1 2024 to Feb 27 2025 23:59:59" do
        expect(date_service.cycle_index).to eq(0)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2024-03-01"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2025-02-27").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 28 2025 (cycle 1, clamped)" do
      let(:billing_at) { Time.zone.parse("2025-02-28") }

      it "is cycle 1 from Feb 28 2025 to Feb 27 2026 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2025-02-28"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2026-02-27").end_of_day)
      end
    end

    context "when billing_at is exactly Feb 29 2028 (cycle 4, restored to 29 in leap year)" do
      let(:billing_at) { Time.zone.parse("2028-02-29") }

      it "is cycle 4 from Feb 29 2028 to Feb 27 2029 23:59:59" do
        expect(date_service.cycle_index).to eq(4)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2028-02-29"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2029-02-27").end_of_day)
      end
    end
  end

  context "with billing_anchor_date and biennial (count=2)" do
    # started_at = Mar 15 2026, anchor Jun 15, count=2 (every 2 years).
    # Cycles:
    #   cycle 0: Mar 15 2026 → Jun 14 2026 23:59:59  (partial, 3 months)
    #   cycle 1: Jun 15 2026 → Jun 14 2028 23:59:59
    #   cycle 2: Jun 15 2028 → Jun 14 2030 23:59:59
    let(:billing_anchor_date) { Date.new(2025, 6, 15) }
    let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "year", billing_interval_count: 2) }

    context "when billing_at is exactly Jun 15 2026 (cycle 1, first full biennial)" do
      let(:billing_at) { Time.zone.parse("2026-06-15") }

      it "is cycle 1 from Jun 15 2026 to Jun 14 2028 23:59:59" do
        expect(date_service.cycle_index).to eq(1)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2026-06-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2028-06-14").end_of_day)
      end
    end

    context "when billing_at is exactly Jun 15 2028 (cycle 2)" do
      let(:billing_at) { Time.zone.parse("2028-06-15") }

      it "is cycle 2 from Jun 15 2028 to Jun 14 2030 23:59:59" do
        expect(date_service.cycle_index).to eq(2)
        expect(date_service.from_datetime).to eq(Time.zone.parse("2028-06-15"))
        expect(date_service.to_datetime).to eq(Time.zone.parse("2030-06-14").end_of_day)
      end
    end
  end
end
