# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Phase do
  describe ".default" do
    subject(:phase) { described_class.default }

    # A card with no configured phases is a card with exactly one: its own cadence, its own
    # price, for as long as it runs. The walk needs a phase that never ends or it stops
    # producing cycles.
    it "runs for as long as the card does" do
      expect(phase).to be_unbounded
    end

    it "prices at the card's own rate" do
      expect(phase.rate_override).to be_nil
    end

    it "has no code, because nothing persisted it" do
      expect(phase.code).to be_nil
    end
  end

  describe "#unbounded?" do
    it "is unbounded when no cycle count was given" do
      expect(described_class.new(code: "tail", billing_interval_cycle_count: nil, rate_override: nil))
        .to be_unbounded
    end

    it "is bounded by a cycle count, however large" do
      expect(described_class.new(code: "intro", billing_interval_cycle_count: 1, rate_override: nil))
        .not_to be_unbounded
    end
  end

  # A phase of zero cycles produced nothing and left the cursor where it was, so the walk
  # skipped it in silence. It is not a length the domain has a meaning for.
  describe "validation" do
    it "rejects a phase that lasts no cycles" do
      expect { described_class.new(code: "empty", billing_interval_cycle_count: 0, rate_override: nil) }
        .to raise_error(ArgumentError, /positive whole number of cycles/)
    end

    it "rejects a length that is not a whole number" do
      [1.5, "3"].each do |count|
        expect { described_class.new(code: "fractional", billing_interval_cycle_count: count, rate_override: nil) }
          .to raise_error(ArgumentError, /positive whole number of cycles/)
      end
    end

    it "still allows nil, which is what running to the end means" do
      expect { described_class.new(code: "tail", billing_interval_cycle_count: nil, rate_override: nil) }
        .not_to raise_error
    end
  end
end
