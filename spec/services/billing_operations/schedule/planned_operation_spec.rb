# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::Schedule::PlannedOperation do
  let(:cycle_started_at) { Time.utc(2026, 11, 1, 7) }
  let(:billing_at) { Time.utc(2026, 11, 10, 8) }
  let(:termination_billing_at) { nil }
  let(:cycle) { instance_double(Billing::Cycle, started_at: cycle_started_at) }
  let(:obligation) { Billing::Obligation.new(cycle:, segments: [], billing_at:, terms: nil, termination_billing_at:) }

  describe ".from_obligation" do
    subject(:plan) { described_class.from_obligation(obligation, after:) }

    let(:after) { nil }

    it "uses the natural cycle and billing date without changing the obligation" do
      expect(plan).to have_attributes(cycle_started_at:, billing_at:)
      expect(obligation.billing_at).to eq(billing_at)
    end

    context "when the obligation is missing" do
      let(:obligation) { nil }

      it "returns no plan" do
        expect(plan).to be_nil
      end
    end

    context "when termination follows the planned end" do
      let(:termination_billing_at) { Time.utc(2026, 11, 15) }

      it "keeps the natural final date without a preceding operation" do
        expect(plan).to have_attributes(cycle_started_at:, billing_at:)
        expect(obligation.billing_at).to eq(billing_at)
      end

      context "with a preceding operation" do
        let(:after) { Time.utc(2026, 11, 5) }

        it "maps the termination date without changing the natural obligation" do
          expect(plan).to have_attributes(cycle_started_at:, billing_at: termination_billing_at)
          expect(obligation.billing_at).to eq(billing_at)
        end
      end

      context "when the preceding operation is at the natural date" do
        let(:after) { billing_at }

        it "keeps the natural date" do
          expect(plan.billing_at).to eq(billing_at)
        end
      end
    end
  end

  describe "#due_by?" do
    subject(:plan) { described_class.new(obligation:, billing_at:) }

    it "is due at the inclusive cutoff without an upper bound" do
      expect(plan.due_by?(billing_at)).to be(true)
      expect(plan.due_by?(billing_at, before: nil)).to be(true)
    end

    it "is not due before its billing date" do
      expect(plan.due_by?(billing_at - 1.second)).to be(false)
    end

    it "excludes the upper bound itself" do
      expect(plan.due_by?(billing_at, before: billing_at)).to be(false)
    end

    it "is due before the upper bound when at the cutoff" do
      expect(plan.due_by?(billing_at, before: billing_at + 1.second)).to be(true)
    end
  end
end
