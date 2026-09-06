# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Calendar do
  # Zones chosen for what they break: a whole-hour DST shift, a half-hour offset with no
  # DST at all, southern-hemisphere DST running the other way round, and UTC as control.
  timezones = %w[UTC America/New_York Europe/Paris Asia/Kolkata Pacific/Auckland]

  def monthly = Billing::Interval.new(count: 1, unit: :month)

  def calendar_in(timezone, anchor_date: Date.new(2024, 1, 1), interval: monthly)
    described_class.new(anchor_date:, interval:, timezone:)
  end

  # Cut points expressed as fractions of the window, so the same partition works for a
  # one-day cycle and a one-year one. The first and last instants of the cycle are cuts
  # too: a zero-length piece must contribute exactly nothing, not a rounding crumb.
  def cuts_in(window)
    span = (window.end - window.begin).to_i
    fractional = [0, 0.013, 0.2, 0.5, 0.517, 0.99].map { |fraction| window.begin + (span * fraction).round }

    [*fractional, window.end - 1.second]
  end

  # The invariant: partition a cycle any way you like and the shares add back up to it.
  def partition_sum(calendar, window, cuts)
    [window.begin, *cuts, window.end].each_cons(2).sum { |from, to| calendar.proration_ratio(from, to) }
  end

  describe "#window_containing" do
    subject(:calendar) { calendar_in("UTC", anchor_date: Date.new(2024, 2, 1)) }

    it "returns the window holding the timestamp" do
      expect(calendar.window_containing(Time.utc(2024, 2, 15, 12))).to eq(Time.utc(2024, 2, 1)...Time.utc(2024, 3, 1))
    end

    it "is half-open" do
      expect(calendar.window_containing(Time.utc(2024, 2, 15, 12)).exclude_end?).to be(true)
    end

    it "opens the window on a boundary instant" do
      expect(calendar.window_containing(Time.utc(2024, 3, 1)).begin).to eq(Time.utc(2024, 3, 1))
    end

    it "keeps the instant before a boundary in the previous window" do
      expect(calendar.window_containing(Time.utc(2024, 3, 1) - 1.second)).to eq(Time.utc(2024, 2, 1)...Time.utc(2024, 3, 1))
    end

    it "hands consecutive windows a shared instant" do
      window = calendar.window_containing(Time.utc(2024, 2, 15))

      expect(calendar.window_containing(window.end).begin).to eq(window.end)
    end

    context "with a timestamp before the anchor" do
      it "returns the window one step back" do
        expect(calendar.window_containing(Time.utc(2024, 1, 15))).to eq(Time.utc(2024, 1, 1)...Time.utc(2024, 2, 1))
      end

      it "returns a window many steps back" do
        expect(calendar.window_containing(Time.utc(2023, 2, 15))).to eq(Time.utc(2023, 2, 1)...Time.utc(2023, 3, 1))
      end

      it "keeps the instant before the anchor out of window 0" do
        expect(calendar.window_containing(Time.utc(2024, 2, 1) - 1.second).end).to eq(Time.utc(2024, 2, 1))
      end
    end

    context "with a month-end anchor" do
      subject(:calendar) { calendar_in("UTC", anchor_date: Date.new(2023, 1, 31)) }

      it "chains 14 windows without drifting, through a leap February" do
        window = calendar.window_containing(Time.utc(2023, 1, 31))

        starts = Array.new(14) do
          window = calendar.window_containing(window.end)
          window.begin
        end

        expect(starts).to eq(
          [
            Time.utc(2023, 2, 28),
            Time.utc(2023, 3, 31),
            Time.utc(2023, 4, 30),
            Time.utc(2023, 5, 31),
            Time.utc(2023, 6, 30),
            Time.utc(2023, 7, 31),
            Time.utc(2023, 8, 31),
            Time.utc(2023, 9, 30),
            Time.utc(2023, 10, 31),
            Time.utc(2023, 11, 30),
            Time.utc(2023, 12, 31),
            Time.utc(2024, 1, 31),
            Time.utc(2024, 2, 29),
            Time.utc(2024, 3, 31)
          ]
        )
      end

      it "does not lose the 31st after a short month" do
        expect(calendar.window_containing(Time.utc(2023, 3, 15))).to eq(Time.utc(2023, 2, 28)...Time.utc(2023, 3, 31))
      end
    end

    context "with other cadences" do
      it "walks daily" do
        calendar = calendar_in("UTC", interval: Billing::Interval.new(count: 1, unit: :day))

        expect(calendar.window_containing(Time.utc(2024, 1, 10, 13))).to eq(Time.utc(2024, 1, 10)...Time.utc(2024, 1, 11))
      end

      it "walks fortnightly" do
        calendar = calendar_in("UTC", interval: Billing::Interval.new(count: 2, unit: :week))

        expect(calendar.window_containing(Time.utc(2024, 1, 10))).to eq(Time.utc(2024, 1, 1)...Time.utc(2024, 1, 15))
      end

      it "walks quarterly" do
        calendar = calendar_in("UTC", interval: Billing::Interval.new(count: 3, unit: :month))

        expect(calendar.window_containing(Time.utc(2024, 5, 10))).to eq(Time.utc(2024, 4, 1)...Time.utc(2024, 7, 1))
      end

      it "walks yearly from a leap-day anchor" do
        calendar = calendar_in("UTC", anchor_date: Date.new(2024, 2, 29), interval: Billing::Interval.new(count: 1, unit: :year))

        expect(calendar.window_containing(Time.utc(2025, 3, 1))).to eq(Time.utc(2025, 2, 28)...Time.utc(2026, 2, 28))
      end
    end

    context "with a timezone behind UTC" do
      subject(:calendar) { calendar_in("America/New_York", anchor_date: Date.new(2024, 2, 1)) }

      it "puts boundary 0 at local midnight" do
        expect(calendar.window_containing(Time.utc(2024, 2, 15)).begin).to eq(Time.utc(2024, 2, 1, 5))
      end

      it "keeps an instant that is still yesterday locally in the previous window" do
        expect(calendar.window_containing(Time.utc(2024, 2, 1, 4, 59)).end).to eq(Time.utc(2024, 2, 1, 5))
      end
    end

    context "with a half-hour offset timezone" do
      subject(:calendar) { calendar_in("Asia/Kolkata", anchor_date: Date.new(2024, 2, 1)) }

      it "puts boundary 0 at local midnight" do
        expect(calendar.window_containing(Time.utc(2024, 2, 15)).begin).to eq(Time.utc(2024, 1, 31, 18, 30))
      end
    end

    context "when the window spans a DST transition" do
      subject(:calendar) { calendar_in("Europe/Paris", anchor_date: Date.new(2024, 3, 1)) }

      it "keeps both boundaries at local midnight even though the UTC offset changes" do
        expect(calendar.window_containing(Time.utc(2024, 3, 15))).to eq(Time.utc(2024, 2, 29, 23)...Time.utc(2024, 3, 31, 22))
      end
    end
  end

  describe "#covered_days" do
    subject(:calendar) { calendar_in("Europe/Paris", anchor_date: Date.new(2024, 6, 1)) }

    let(:paris) { Time.find_zone!("Europe/Paris") }

    it "counts a whole month" do
      expect(calendar.covered_days(paris.local(2024, 6, 1), paris.local(2024, 7, 1))).to eq(30)
    end

    it "counts the opening day when the window opens at midnight" do
      expect(calendar.covered_days(paris.local(2024, 6, 1), paris.local(2024, 6, 16, 9, 30))).to eq(16)
    end

    it "does not count the day a window opens in the middle of" do
      expect(calendar.covered_days(paris.local(2024, 6, 16, 9, 30), paris.local(2024, 7, 1))).to eq(14)
    end

    it "counts nothing inside a single day" do
      expect(calendar.covered_days(paris.local(2024, 6, 16, 9, 30), paris.local(2024, 6, 16, 23, 59))).to eq(0)
    end

    it "counts nothing for an empty window" do
      expect(calendar.covered_days(paris.local(2024, 6, 16, 9, 30), paris.local(2024, 6, 16, 9, 30))).to eq(0)
    end

    it "splits a cut day between the two pieces exactly once" do
      cut = paris.local(2024, 6, 16, 9, 30)
      pieces = [
        calendar.covered_days(paris.local(2024, 6, 1), cut),
        calendar.covered_days(cut, paris.local(2024, 7, 1))
      ]

      expect(pieces.sum).to eq(30)
    end

    it "counts a 23-hour day as a day" do
      expect(calendar.covered_days(paris.local(2024, 3, 1), paris.local(2024, 4, 1))).to eq(31)
    end

    it "counts a 25-hour day as a day" do
      expect(calendar.covered_days(paris.local(2024, 10, 1), paris.local(2024, 11, 1))).to eq(31)
    end

    it "reads its arguments in the calendar timezone, not in theirs" do
      # Jul 1 00:00 Paris is Jun 30 22:00 UTC: the day belongs to July here.
      expect(calendar.covered_days(Time.utc(2024, 5, 31, 22), Time.utc(2024, 6, 30, 22))).to eq(30)
    end
  end

  describe "#proration_ratio" do
    subject(:calendar) { calendar_in("UTC", anchor_date: Date.new(2024, 6, 1)) }

    it "returns a Rational" do
      expect(calendar.proration_ratio(Time.utc(2024, 6, 1), Time.utc(2024, 6, 16))).to be_a(Rational)
    end

    it "is 1 for the whole window" do
      expect(calendar.proration_ratio(Time.utc(2024, 6, 1), Time.utc(2024, 7, 1))).to eq(1)
    end

    it "is 0 for an empty window" do
      expect(calendar.proration_ratio(Time.utc(2024, 6, 16), Time.utc(2024, 6, 16))).to eq(0)
    end

    it "is the share of days for a window opening at midnight" do
      expect(calendar.proration_ratio(Time.utc(2024, 6, 1), Time.utc(2024, 6, 16, 9, 30))).to eq(Rational(8, 15))
    end

    it "is the share of days for a window opening mid-day" do
      expect(calendar.proration_ratio(Time.utc(2024, 6, 16, 9, 30), Time.utc(2024, 7, 1))).to eq(Rational(7, 15))
    end

    it "raises when to is before from" do
      expect { calendar.proration_ratio(Time.utc(2024, 6, 16), Time.utc(2024, 6, 15)) }
        .to raise_error(ArgumentError, /is before from/)
    end

    it "raises when to runs past the window holding from" do
      expect { calendar.proration_ratio(Time.utc(2024, 6, 16), Time.utc(2024, 7, 2)) }
        .to raise_error(ArgumentError, /past the end of the window/)
    end

    it "raises when to runs one second past the window holding from" do
      expect { calendar.proration_ratio(Time.utc(2024, 6, 16), Time.utc(2024, 7, 1) + 1.second) }
        .to raise_error(ArgumentError, /past the end of the window/)
    end

    it "accepts a window ending exactly on the boundary" do
      expect(calendar.proration_ratio(Time.utc(2024, 6, 16), Time.utc(2024, 7, 1))).to eq(Rational(1, 2))
    end

    # The bug this engine exists to kill: the old date maths ceil'd both halves of a cut
    # cycle and billed 31 days of a 30-day June.
    it "splits a cycle cut mid-day into shares that sum to exactly 1" do
      cut = Time.utc(2024, 6, 15, 9, 30)
      shares = [
        calendar.proration_ratio(Time.utc(2024, 6, 1), cut),
        calendar.proration_ratio(cut, Time.utc(2024, 7, 1))
      ]

      expect(shares.sum).to eq(1)
    end

    describe "the partition invariant" do
      timezones.each do |timezone|
        it "holds for every month of the year in #{timezone}" do
          calendar = calendar_in(timezone)

          sums = (1..12).map do |month|
            window = calendar.window_containing(Time.find_zone!(timezone).local(2024, month, 15, 12))
            partition_sum(calendar, window, cuts_in(window))
          end

          expect(sums).to eq(Array.new(12, 1))
        end
      end

      it "holds for a daily cadence through a DST transition" do
        calendar = calendar_in("Europe/Paris", anchor_date: Date.new(2024, 3, 1), interval: Billing::Interval.new(count: 1, unit: :day))

        sums = (25..31).map do |day|
          window = calendar.window_containing(Time.find_zone!("Europe/Paris").local(2024, 3, day, 12))
          partition_sum(calendar, window, cuts_in(window))
        end

        expect(sums).to eq(Array.new(7, 1))
      end

      it "holds for a fortnightly cadence" do
        calendar = calendar_in("Pacific/Auckland", interval: Billing::Interval.new(count: 2, unit: :week))

        sums = (1..12).map do |month|
          window = calendar.window_containing(Time.find_zone!("Pacific/Auckland").local(2024, month, 15, 12))
          partition_sum(calendar, window, cuts_in(window))
        end

        expect(sums).to eq(Array.new(12, 1))
      end

      it "holds for a yearly cadence over a leap year" do
        calendar = calendar_in("America/New_York", anchor_date: Date.new(2023, 3, 1), interval: Billing::Interval.new(count: 1, unit: :year))

        sums = (2023..2026).map do |year|
          window = calendar.window_containing(Time.find_zone!("America/New_York").local(year, 6, 15, 12))
          partition_sum(calendar, window, cuts_in(window))
        end

        expect(sums).to eq(Array.new(4, 1))
      end

      it "holds when the cuts land on the DST transition itself" do
        calendar = calendar_in("Europe/Paris", anchor_date: Date.new(2024, 3, 1))
        paris = Time.find_zone!("Europe/Paris")
        window = calendar.window_containing(paris.local(2024, 3, 15))
        cuts = [paris.local(2024, 3, 31, 1, 30), paris.local(2024, 3, 31, 3, 30)]

        expect(partition_sum(calendar, window, cuts)).to eq(1)
      end

      it "holds when the cuts land on a repeated hour" do
        calendar = calendar_in("America/New_York", anchor_date: Date.new(2024, 11, 1))
        new_york = Time.find_zone!("America/New_York")
        window = calendar.window_containing(new_york.local(2024, 11, 15))
        cuts = [new_york.local(2024, 11, 3, 1, 30), new_york.local(2024, 11, 3, 1, 30) + 1.hour]

        expect(partition_sum(calendar, window, cuts)).to eq(1)
      end

      it "holds for a cycle before the anchor" do
        calendar = calendar_in("Europe/Paris", anchor_date: Date.new(2024, 6, 1))
        window = calendar.window_containing(Time.find_zone!("Europe/Paris").local(2022, 2, 15))

        expect(partition_sum(calendar, window, cuts_in(window))).to eq(1)
      end
    end
  end

  # Boundaries are cached, and no assertion on a returned value can see that — so these
  # examples count the arithmetic instead. Without them the cache can be dropped by a
  # refactor with every other example still green.
  describe "boundary memoization" do
    # A real Interval behind a spy: the arithmetic is untouched, only the calls are
    # counted. `steps_between` runs its own `advance` on the real interval, out of the
    # spy's reach, so what this counts is exactly the boundaries the calendar computed.
    def counting_interval(real_interval = monthly)
      instance_double(Billing::Interval).tap do |spy|
        allow(spy).to receive(:advance) { |timestamp, steps| real_interval.advance(timestamp, steps) }
        allow(spy).to receive(:steps_between) { |from, to| real_interval.steps_between(from, to) }
      end
    end

    # The walk the engine actually performs: each cycle asks for the window opening where
    # the previous one closed.
    def walk(calendar, windows)
      window = calendar.window_containing(Time.utc(2023, 1, 31))

      Array.new(windows) do
        window = calendar.window_containing(window.end)
        window.begin
      end
    end

    subject(:calendar) { calendar_in("UTC", anchor_date: Date.new(2023, 1, 31), interval:) }

    let(:interval) { counting_interval }

    it "computes one boundary per window walked, not two" do
      walk(calendar, 50)

      # 51 windows are fenced by 52 boundaries; uncached, each window would cost 2.
      expect(interval).to have_received(:advance).exactly(52).times
    end

    it "computes nothing the second time a boundary is asked for" do
      calendar.window_containing(Time.utc(2023, 2, 15))
      calendar.window_containing(Time.utc(2023, 2, 20))

      expect(interval).to have_received(:advance).twice
    end

    it "returns the boundaries of a month-end anchor on a cold calendar" do
      expect(walk(calendar, 4)).to eq([Time.utc(2023, 2, 28), Time.utc(2023, 3, 31), Time.utc(2023, 4, 30), Time.utc(2023, 5, 31)])
    end

    it "returns the same boundaries once they come from the cache" do
      walk(calendar, 4)

      expect(walk(calendar, 4)).to eq([Time.utc(2023, 2, 28), Time.utc(2023, 3, 31), Time.utc(2023, 4, 30), Time.utc(2023, 5, 31)])
    end

    it "keeps negative indices apart from positive ones" do
      calendar.window_containing(Time.utc(2023, 3, 15))

      expect(calendar.window_containing(Time.utc(2023, 1, 15))).to eq(Time.utc(2022, 12, 31)...Time.utc(2023, 1, 31))
    end

    it "computes nothing the second time a negative boundary is asked for" do
      calendar.window_containing(Time.utc(2022, 11, 15))
      calendar.window_containing(Time.utc(2022, 11, 20))

      expect(interval).to have_received(:advance).twice
    end
  end
end
