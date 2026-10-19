# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::TimestampWindow do
  let(:now) { Time.zone.parse("2026-10-14T12:00:00Z") }

  describe ".within?" do
    it "accepts a timestamp in the supported range" do
      expect(described_class.within?(Time.zone.parse("2020-01-01"), now:)).to be(true)
    end

    it "rejects a timestamp before 1970 or from 2300" do
      expect(described_class.within?(Time.zone.at(-1), now:)).to be(false)
      expect(described_class.within?(Time.zone.parse("2300-01-01"), now:)).to be(false)
    end

    context "when no window is configured" do
      it "accepts old and future timestamps" do
        expect(described_class.within?(Time.zone.parse("1971-01-01"), now:)).to be(true)
        expect(described_class.within?(Time.zone.parse("2200-01-01"), now:)).to be(true)
      end
    end

    context "when a window is configured" do
      before do
        stub_const("Events::TimestampWindow::MAX_PAST_DAYS", 30)
        stub_const("Events::TimestampWindow::MAX_FUTURE_HOURS", 24)
      end

      it "rejects timestamps outside it" do
        expect(described_class.within?(now - 31.days, now:)).to be(false)
        expect(described_class.within?(now + 25.hours, now:)).to be(false)
      end

      it "accepts timestamps inside it" do
        expect(described_class.within?(now - 29.days, now:)).to be(true)
        expect(described_class.within?(now + 23.hours, now:)).to be(true)
      end
    end
  end
end
