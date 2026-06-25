# frozen_string_literal: true

require "rails_helper"

# Weekly interval. Boundaries fall every `interval_count` weeks on the anchor's
# weekday. Calendar billing anchors to Monday; anniversary to the subscription day.
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
  let(:interval_unit) { :week }
  let(:billing_timing) { :arrears }
  let(:timezone) { "UTC" }
  let(:billing_anchor_date) { Date.new(2022, 1, 3) } # a Monday

  context "arrears" do
    let(:billing_at) { Time.utc(2022, 1, 17) } # a Monday, a boundary

    it "bills the week that just closed, anchored on the weekday" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 10))
      expect(result.period_to).to match_datetime(Time.utc(2022, 1, 16, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 1, 24))
      expect(result.period_from.wday).to eq(1) # Monday
    end

    it_behaves_like "billing period boundaries"

    context "when billing_at is mid-week" do
      let(:billing_at) { Time.utc(2022, 1, 19) } # a Wednesday

      it "snaps to the week boundary" do
        expect(result.period_from).to eq(Time.utc(2022, 1, 10))
        expect(result.period_to).to match_datetime(Time.utc(2022, 1, 16, 23, 59, 59))
      end
    end
  end

  context "advance" do
    let(:billing_timing) { :advance }
    let(:billing_at) { Time.utc(2022, 1, 17) }

    it "bills the week that just started" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 17))
      expect(result.period_to).to match_datetime(Time.utc(2022, 1, 23, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 1, 24))
    end
  end

  context "multi-week interval (every 2 weeks), arrears" do
    let(:interval_count) { 2 }
    let(:billing_at) { Time.utc(2022, 1, 17) }

    it "spans two weeks" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 3))
      expect(result.period_to).to match_datetime(Time.utc(2022, 1, 16, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 1, 31))
    end
  end

  context "across a DST change, in a customer timezone" do
    let(:timezone) { "America/New_York" }
    let(:billing_anchor_date) { Date.new(2022, 3, 7) } # Monday; the week Mar 7-14 spans US spring-forward (Mar 13)
    let(:billing_at) { Time.utc(2022, 3, 14, 12) }

    let(:zone) { ActiveSupport::TimeZone["America/New_York"] }

    # The billed week [Mar 7, Mar 14) straddles the Mar 13 spring-forward: it starts
    # in EST (UTC-5) and ends in EDT (UTC-4), yet both boundaries stay on local
    # Monday midnight.
    it "keeps boundaries on local midnight despite the offset change" do
      expect(result.period_from.in_time_zone(zone)).to eq(zone.local(2022, 3, 7))
      expect(result.period_from).to eq(Time.utc(2022, 3, 7, 5))            # EST: 00:00 -> 05:00 UTC
      expect(result.period_to).to match_datetime(Time.utc(2022, 3, 14, 3, 59, 59)) # Mar 13 23:59:59 EDT
      expect(result.next_billing_at.in_time_zone(zone)).to eq(zone.local(2022, 3, 21))
      expect(result.next_billing_at).to eq(Time.utc(2022, 3, 21, 4))       # EDT: 00:00 -> 04:00 UTC
    end
  end
end
