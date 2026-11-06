# frozen_string_literal: true

require "rails_helper"

RSpec.describe "have_normalized_timestamps matcher" do # rubocop:disable RSpec/DescribeClass
  subject(:matcher) { have_normalized_timestamps }

  it "accepts datetimes to the microsecond and dates, nested in records and lists" do
    payload = {
      rate_card: {
        created_at: "2026-10-16T10:00:00.123456Z",
        rates: [{effective_from: "2026-10-16T00:00:00.000000Z", billing_anchor_date: "2026-10-16"}]
      }
    }

    expect(matcher.matches?(payload)).to be(true)
  end

  it "ignores the values that are not shaped like a date" do
    payload = {
      code: "2026-10-16-promo",
      name: "2026-10-16 launch",
      description: "October 2026-10-16",
      count: 20261016,
      deleted_at: nil,
      list: ["", true]
    }

    expect(matcher.matches?(payload)).to be(true)
  end

  {
    "whole seconds" => "2026-10-16T10:00:00Z",
    "milliseconds" => "2026-10-16T10:00:00.123Z",
    "an offset" => "2026-10-16T12:00:00.123456+02:00",
    "a space separator" => "2026-10-16 10:00:00 UTC",
    "no time zone" => "2026-10-16T10:00:00.123456"
  }.each do |description, value|
    it "rejects a value with #{description}, naming its path" do
      payload = {contract: {applied_rate_cards: [{next_billing_at: value}]}}

      expect(matcher.matches?(payload)).to be(false)
      expect(matcher.failure_message).to include(%("contract.applied_rate_cards[0].next_billing_at" => #{value.inspect}))
    end
  end

  it "checks a list at the root" do
    expect(matcher.matches?([{created_at: "2026-10-16T10:00:00Z"}])).to be(false)
    expect(matcher.failure_message).to include(%("[0].created_at" => "2026-10-16T10:00:00Z"))
  end
end
