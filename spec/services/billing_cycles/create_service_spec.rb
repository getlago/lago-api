# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::CreateService do
  subject(:result) { described_class.call(contract_rate_card:, cycles:) }

  let(:cycles) { [cycle] }
  let(:contract_rate_card) { create(:contract_rate_card) }
  let(:timezone) { "UTC" }
  let(:zone) { ActiveSupport::TimeZone[timezone] }
  let(:anchor_date) { Date.new(2026, 6, 1) }
  let(:started_at) { zone.parse("2026-06-01") }
  let(:ended_at) { zone.parse("2026-07-01") }
  let(:interval) { Billing::Interval.new(count: 1, unit: :month) }
  let(:calendar) { Billing::Calendar.new(anchor_date:, interval:, timezone:) }
  let(:cycle) do
    Billing::Cycle.new(index: 0, started_at:, ended_at:, phase: Billing::Phase.default, calendar:)
  end

  describe "#call" do
    it "persists the period and its calendar reference" do
      expect(result).to be_success
      expect(result.billing_cycles.sole).to have_attributes(
        organization_id: contract_rate_card.organization_id,
        contract_rate_card_id: contract_rate_card.id,
        cycle_index: 0,
        started_at:,
        ended_at:,
        reference_started_at: started_at,
        timezone:
      )
    end

    it "reuses the same cycle on retry" do
      original = result.billing_cycles.sole

      expect { described_class.call!(contract_rate_card:, cycles:) }.not_to change(BillingCycle, :count)
      expect(described_class.call!(contract_rate_card:, cycles:).billing_cycles.sole).to eq(original)
    end

    context "without cycles" do
      let(:cycles) { [] }

      it "returns an empty result without creating periods" do
        expect { result }.not_to change(BillingCycle, :count)
        expect(result).to be_success
        expect(result.billing_cycles).to eq([])
      end
    end

    context "with repeated pricing slices of the same cycle" do
      let(:cycles) { [cycle, cycle] }

      it "returns one persisted period" do
        expect { result }.to change(BillingCycle, :count).by(1)
        expect(result.billing_cycles.map(&:cycle_index)).to eq([0])
      end
    end

    context "with an initial stub" do
      let(:started_at) { zone.parse("2026-06-15") }

      it "keeps the full denominator rather than the service start" do
        expect(result.billing_cycles.sole).to have_attributes(
          started_at:,
          reference_started_at: zone.parse("2026-06-01"),
          ended_at: zone.parse("2026-07-01")
        )
      end
    end

    context "when service ends early" do
      let(:ended_at) { zone.parse("2026-06-11") }

      it "keeps the nominal end for proration" do
        expect(result.billing_cycles.sole.ended_at).to eq(zone.parse("2026-07-01"))
      end

      context "with a cycle already materialized before termination" do
        let!(:existing) do
          create(:billing_cycle, organization: contract_rate_card.organization,
            contract_rate_card:, started_at:, ended_at: zone.parse("2026-07-01"))
        end

        it "reuses the original cycle without changing its reference" do
          expect { result }.not_to change { existing.reload.attributes }
          expect(result).to be_success
          expect(result.billing_cycles.sole).to eq(existing)
        end
      end
    end

    context "with a daylight saving transition" do
      let(:timezone) { "Europe/Paris" }
      let(:anchor_date) { Date.new(2026, 3, 1) }
      let(:started_at) { zone.parse("2026-03-01") }
      let(:ended_at) { zone.parse("2026-04-01") }

      it "stores the local calendar boundaries as UTC instants" do
        expect(result.billing_cycles.sole).to have_attributes(
          started_at: Time.utc(2026, 2, 28, 23),
          ended_at: Time.utc(2026, 3, 31, 22),
          reference_started_at: Time.utc(2026, 2, 28, 23),
          timezone: "Europe/Paris"
        )
      end
    end

    context "with a phase using a weekly cadence" do
      let(:interval) { Billing::Interval.new(count: 1, unit: :week) }
      let(:ended_at) { zone.parse("2026-06-08") }

      it "persists the resolved cadence rather than assuming monthly billing" do
        expect(result.billing_cycles.sole.ended_at).to eq(ended_at)
      end
    end

    context "when the persisted calendar differs" do
      let!(:existing) do
        create(:billing_cycle, organization: contract_rate_card.organization,
          contract_rate_card:, started_at:, ended_at: zone.parse("2026-06-08"))
      end

      it "reports the conflict without rewriting the previous reference" do
        expect { result }.not_to change { existing.reload.attributes }
        expect(result.error.messages).to eq(billing_cycle: ["calendar_conflict"])
      end

      context "with another new cycle in the same batch" do
        let(:cycles) { [next_cycle, cycle] }
        let(:next_cycle) do
          Billing::Cycle.new(index: 1, started_at: zone.parse("2026-07-01"),
            ended_at: zone.parse("2026-08-01"), phase: Billing::Phase.default, calendar:)
        end

        it "rolls back newly inserted cycles and returns no partial result" do
          expect { result }.not_to change(BillingCycle, :count)
          expect(result.error.messages).to eq(billing_cycle: ["calendar_conflict"])
          expect(result.billing_cycles).to eq([])
        end
      end
    end
  end
end
