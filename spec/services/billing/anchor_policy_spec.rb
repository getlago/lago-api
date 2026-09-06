# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::AnchorPolicy do
  let(:original_anchor) { Date.new(2024, 1, 1) }
  let(:cursor_date) { Date.new(2024, 2, 15) }

  describe described_class::Realigning do
    it "moves the anchor to the day the cadence changed" do
      expect(described_class.anchor_after_cadence_change(original_anchor, cursor_date)).to eq(cursor_date)
    end

    # The anchor is a reference day, not a start date, so a change taking effect before the
    # anchor moves it backwards just as readily as forwards.
    it "moves it backwards when the change precedes the anchor" do
      expect(described_class.anchor_after_cadence_change(original_anchor, Date.new(2023, 11, 20)))
        .to eq(Date.new(2023, 11, 20))
    end

    it "keeps only the latest change, since each one re-rules the calendar" do
      first = described_class.anchor_after_cadence_change(original_anchor, cursor_date)

      expect(described_class.anchor_after_cadence_change(first, Date.new(2024, 3, 20)))
        .to eq(Date.new(2024, 3, 20))
    end
  end

  # The walk hands this answer straight to Calendar, which reads it as a date in the
  # customer's timezone. A policy handing back a Time would silently move boundary 0 off
  # local midnight — the guard matters for any policy added later, not just this one.
  it "answers with a Date" do
    answer = described_class::Realigning.anchor_after_cadence_change(original_anchor, cursor_date)

    expect(answer).to be_a(Date)
  end
end
