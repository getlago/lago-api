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

    it "rejects an invalid billing scope" do
      [nil, "unknown", 123, false].each do |scope|
        expect { described_class.new(timing: :arrears, prorated: true, billing_scope: scope) }
          .to raise_error(ArgumentError, /unknown billing scope/)
      end
    end

    it "accepts a scope symbol as well as the enum value" do
      expect(described_class.new(timing: :arrears, prorated: true, billing_scope: :segment).cycle_scope?).to be(false)
      expect(described_class.new(timing: :arrears, prorated: true, billing_scope: "cycle").cycle_scope?).to be(true)
    end

    it "rejects a non-boolean coverage-end flag" do
      [nil, "true", 1].each do |flag|
        expect { described_class.new(timing: :advance, prorated: true, due_on_coverage_end: flag) }
          .to raise_error(ArgumentError, /due_on_coverage_end must be true or false/)
      end
    end
  end

  # The one place in the engine that knows what advance and arrears mean.
  describe "#pricing_anchor_for" do
    it "anchors pricing at the window close in arrears" do
      expect(terms.pricing_anchor_for(window)).to eq(window.ended_at)
    end

    it "anchors pricing at the window opening in advance" do
      expect(described_class.new(timing: :advance, prorated: true).pricing_anchor_for(window))
        .to eq(window.started_at)
    end

    # It is asked about a whole cycle and about one slice of a cut cycle, and answers each on
    # its own bounds, so a slice can use a cut rather than the cycle's close.
    it "answers on the bounds it is given, whatever kind of window that is" do
      slice = Billing::Segments::Segment.new(started_at: window.started_at, ended_at: Time.utc(2026, 8, 25), rate: nil)

      expect(terms.pricing_anchor_for(slice)).to eq(Time.utc(2026, 8, 25))
    end
  end

  describe "#obligation_billing_at_for" do
    subject(:terms) do
      described_class.new(timing:, prorated: true, billing_scope:, due_on_coverage_end:)
    end

    let(:timing) { :arrears }
    let(:billing_scope) { ContractRateCard::BILLING_SCOPES.fetch(:cycle) }
    let(:due_on_coverage_end) { false }
    let(:cycle) { Billing::Segments::Segment.new(started_at: Time.utc(2026, 8, 1), ended_at: Time.utc(2026, 9, 1), rate: nil) }
    let(:first_slice) { Billing::Segments::Segment.new(started_at: Time.utc(2026, 8, 10), ended_at: Time.utc(2026, 8, 20), rate: nil) }
    let(:last_slice) { Billing::Segments::Segment.new(started_at: Time.utc(2026, 8, 20), ended_at: cycle.ended_at, rate: nil) }
    let(:segments) { [first_slice, last_slice] }

    it "uses the cycle end in arrears" do
      expect(terms.obligation_billing_at_for(cycle:, segments:)).to eq(cycle.ended_at)
      expect(terms.pricing_anchor_for(first_slice)).to eq(first_slice.ended_at)
    end

    context "when billing in advance" do
      let(:timing) { :advance }

      it "uses the first priced start, not the unpriced cycle start" do
        expect(terms.obligation_billing_at_for(cycle:, segments:)).to eq(first_slice.started_at)
        expect(terms.pricing_anchor_for(cycle)).to eq(cycle.started_at)
      end

      context "when regrouping" do
        let(:due_on_coverage_end) { true }

        it "uses the cycle end without changing the terms anchor" do
          expect(terms.obligation_billing_at_for(cycle:, segments:)).to eq(cycle.ended_at)
          expect(terms.pricing_anchor_for(first_slice)).to eq(first_slice.started_at)
        end
      end
    end

    context "with segment scope" do
      let(:billing_scope) { ContractRateCard::BILLING_SCOPES.fetch(:segment) }
      let(:segments) { [first_slice] }

      it "uses the segment end in arrears" do
        expect(terms.obligation_billing_at_for(cycle:, segments:)).to eq(first_slice.ended_at)
      end

      context "when billing in advance" do
        let(:timing) { :advance }

        it "uses the segment start" do
          expect(terms.obligation_billing_at_for(cycle:, segments:)).to eq(first_slice.started_at)
        end

        context "when regrouping" do
          let(:due_on_coverage_end) { true }

          it "uses the segment end while preserving the terms anchor" do
            expect(terms.obligation_billing_at_for(cycle:, segments:)).to eq(first_slice.ended_at)
            expect(terms.pricing_anchor_for(first_slice)).to eq(first_slice.started_at)
          end
        end
      end
    end
  end
end
