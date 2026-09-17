# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Terms do
  subject(:terms) { described_class.new(timing: :arrears, prorated: true) }

  let(:window) { Billing::Segments::Segment.new(started_at: Time.utc(2026, 8, 10), ended_at: Time.utc(2026, 9, 10), rate: nil) }

  it "covers exactly the billing timings the catalog allows" do
    expect(described_class::TIMINGS).to match_array(RateCard::BILLING_TIMINGS.keys)
  end

  describe "validation" do
    it "rejects an unknown timing" do
      expect { described_class.new(timing: :upfront, prorated: true) }
        .to raise_error(ArgumentError, /unknown billing timing/)
    end

    it "rejects a nil timing without blowing up on it" do
      expect { described_class.new(timing: nil, prorated: true) }
        .to raise_error(ArgumentError, /unknown billing timing/)
    end

    it "takes the timing as a string, which is how the enum column reads" do
      expect(described_class.new(timing: "advance", prorated: false).timing).to eq(:advance)
    end

    # The flag decides money, so a nil or a truthy string must not slip through as "on".
    it "rejects a proration flag that is not a boolean" do
      expect { described_class.new(timing: :arrears, prorated: nil) }
        .to raise_error(ArgumentError, /must be true or false/)
      expect { described_class.new(timing: :arrears, prorated: "true") }
        .to raise_error(ArgumentError, /must be true or false/)
    end
  end

  # The one place in the engine that knows what advance and arrears mean.
  describe "#billing_at_for" do
    it "falls due when the window closes in arrears" do
      expect(terms.billing_at_for(window)).to eq(window.ended_at)
    end

    it "falls due when the window opens in advance" do
      expect(described_class.new(timing: :advance, prorated: true).billing_at_for(window))
        .to eq(window.started_at)
    end

    # It is asked about a whole cycle and about one slice of a cut cycle, and answers each on
    # its own bounds — which is what lets a slice fall due on the cut rather than at the
    # cycle's close.
    it "answers on the bounds it is given, whatever kind of window that is" do
      slice = Billing::Segments::Segment.new(started_at: window.started_at, ended_at: Time.utc(2026, 8, 25), rate: nil)

      expect(terms.billing_at_for(slice)).to eq(Time.utc(2026, 8, 25))
    end
  end
end
