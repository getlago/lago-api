# frozen_string_literal: true

require "rails_helper"

# Daily interval. There is no legacy daily engine (it's the trial interval), so no
# parity spec — these pin the new engine's day boundaries directly.
RSpec.describe BillingPeriods::DatesService do
  subject(:result) do
    described_class.call(
      billing_anchor_date:,
      interval_count:,
      interval_unit:,
      billing_timing:,
      timezone:,
      billing_at:
    )
  end

  let(:interval_count) { 1 }
  let(:interval_unit) { :day }
  let(:billing_timing) { :arrears }
  let(:timezone) { "UTC" }
  let(:billing_anchor_date) { Date.new(2022, 1, 1) }

  context "arrears" do
    let(:billing_at) { Time.utc(2022, 1, 5) }

    it "bills the day that just closed" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 4))
      expect(result.period_to).to match_datetime(Time.utc(2022, 1, 4, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 1, 6))
    end

    it_behaves_like "billing period boundaries"
  end

  context "advance" do
    let(:billing_timing) { :advance }
    let(:billing_at) { Time.utc(2022, 1, 5) }

    it "bills the day that just started" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 5))
      expect(result.period_to).to match_datetime(Time.utc(2022, 1, 5, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 1, 6))
    end
  end

  context "multi-day interval (every 3 days), arrears" do
    let(:interval_count) { 3 }
    let(:billing_at) { Time.utc(2022, 1, 7) }

    it "spans three days" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 4))
      expect(result.period_to).to match_datetime(Time.utc(2022, 1, 6, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 1, 10))
    end
  end

  context "across a DST change, in a customer timezone" do
    let(:timezone) { "America/New_York" }
    let(:billing_anchor_date) { Date.new(2022, 3, 13) } # US spring-forward day
    let(:billing_at) { Time.utc(2022, 3, 14, 12) }

    # The billed day (Mar 13) is only 23 hours long: it starts in EST and ends in
    # EDT, but the boundaries stay on local midnight.
    it "keeps day boundaries on local midnight despite the offset change" do
      expect(result.period_from).to eq(Time.utc(2022, 3, 13, 5))            # EST: 00:00 -> 05:00 UTC
      expect(result.period_to).to match_datetime(Time.utc(2022, 3, 14, 3, 59, 59)) # Mar 13 23:59:59 EDT
      expect(result.next_billing_at).to eq(Time.utc(2022, 3, 15, 4))        # EDT: 00:00 -> 04:00 UTC
    end
  end
end
