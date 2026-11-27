# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::Schedule::PlannedOperation do
  let(:cycle_started_at) { Time.utc(2026, 11, 1, 7) }
  let(:billing_at) { Time.utc(2026, 11, 10, 8) }
  let(:termination_billing_at) { nil }
  let(:cycle) { instance_double(Billing::Cycle, started_at: cycle_started_at) }
  let(:coverage_started_at) { cycle_started_at }
  let(:coverage_ended_at) { Time.utc(2026, 12, 1, 8) }
  let(:segment) { double(started_at: coverage_started_at, ended_at: coverage_ended_at) }
  let(:obligation) { Billing::Obligation.new(cycle:, segments: [segment], billing_at:, terms: nil, termination_billing_at:) }

  describe ".from_obligation" do
    subject(:plan) { described_class.from_obligation(obligation, after:) }

    let(:after) { nil }

    it "uses the natural cycle and billing date without changing the obligation" do
      expect(plan).to have_attributes(cycle_started_at:, billing_at:, coverage_started_at:, coverage_ended_at:, obligation:)
      expect(plan.with(billing_at: billing_at + 1.day).obligation).to equal(obligation)
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
end
