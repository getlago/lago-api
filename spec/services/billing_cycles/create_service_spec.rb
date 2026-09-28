# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::CreateService do
  subject(:result) { described_class.call(contract_rate_card:, cycle:) }

  let(:contract_rate_card) { create(:contract_rate_card) }
  let(:timezone) { "UTC" }
  let(:zone) { ActiveSupport::TimeZone[timezone] }
  let(:anchor_date) { Date.new(2026, 1, 1) }
  let(:starts_at) { zone.parse("2026-01-01") }
  let(:ends_at) { nil }
  let(:at) { starts_at }
  let(:phases) { [Billing::Phase.default] }
  let(:rate) do
    build(:rate_card_rate, organization: contract_rate_card.organization, rate_card: contract_rate_card.rate_card,
      effective_from: Time.utc(2026, 1, 1), billing_interval_count: 1, billing_interval_unit: "month")
  end
  let(:walker) do
    Billing::RateCards::CycleWalker.new(rates: [rate], phases:, starts_at:, ends_at:, anchor_date:, timezone:)
  end
  let(:cycle) { walker.walk_to(at).last }

  describe "#call" do
    it "persists the full period and the walker's cycle index" do
      expect { result }.to change(BillingCycle, :count).by(1)
      expect(result).to be_success
      expect(result.billing_cycle).to have_attributes(
        organization_id: contract_rate_card.organization_id,
        contract_rate_card_id: contract_rate_card.id,
        cycle_index: 0, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 2, 1), timezone: "UTC"
      )
    end

    context "when the same cycle is retried" do
      let(:retry_result) { described_class.call(contract_rate_card:, cycle:) }

      it "reuses the row without updating it" do
        original = result.billing_cycle

        expect { retry_result }.not_to change { [BillingCycle.count, original.reload.attributes] }
        expect(retry_result).to be_success
        expect(retry_result.billing_cycle.id).to eq(original.id)
      end
    end

    context "when two writers create the same cycle", transaction: false do
      subject(:results) do
        gate = Queue.new
        threads = writers.map do |writer|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              gate.pop
              writer.call
            end
          end
        end
        writers.size.times { gate << true }
        threads.map(&:value)
      end

      let(:writers) do
        Array.new(2) do
          described_class.new(contract_rate_card: ContractRateCard.find(contract_rate_card.id), cycle:)
        end
      end

      it "returns the same row to both writers" do
        expect(results).to all(be_success)
        expect(results.map { it.billing_cycle.id }.uniq.size).to eq(1)
        expect(contract_rate_card.billing_cycles.count).to eq(1)
      end
    end

    context "when service starts mid-cycle" do
      let(:starts_at) { zone.parse("2026-01-15 14:30") }

      it "preserves the full calendar denominator" do
        expect(result.billing_cycle).to have_attributes(
          started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 2, 1), cycle_index: 0
        )
      end
    end

    context "when service ends mid-cycle" do
      let(:ends_at) { zone.parse("2026-01-21") }

      it "does not truncate the nominal period" do
        expect(cycle.ended_at).to eq(ends_at)
        expect(result.billing_cycle.ended_at).to eq(Time.utc(2026, 2, 1))
      end

      context "with a previously persisted full cycle" do
        let!(:existing) do
          create(:billing_cycle, organization: contract_rate_card.organization, contract_rate_card:)
        end

        it "reuses the original period after termination" do
          expect { result }.not_to change { existing.reload.attributes }
          expect(result).to be_success
          expect(result.billing_cycle).to eq(existing)
        end
      end
    end

    context "with an anchor at the end of the month" do
      let(:anchor_date) { Date.new(2026, 1, 31) }
      let(:starts_at) { zone.parse("2026-01-31") }
      let(:at) { zone.parse("2026-03-01") }

      it "preserves the month-end calendar instead of reanchoring on February 28" do
        expect(result.billing_cycle).to have_attributes(
          cycle_index: 1, started_at: Time.utc(2026, 2, 28), ended_at: Time.utc(2026, 3, 31)
        )
      end
    end

    context "with a daylight saving transition" do
      let(:timezone) { "Europe/Paris" }
      let(:starts_at) { zone.parse("2026-03-01") }
      let(:anchor_date) { Date.new(2026, 3, 1) }

      it "stores local calendar boundaries as UTC instants with their timezone" do
        expect(result.billing_cycle).to have_attributes(
          started_at: Time.utc(2026, 2, 28, 23), ended_at: Time.utc(2026, 3, 31, 22), timezone:
        )
      end
    end

    context "with two weekly intro cycles followed by the monthly default phase" do
      let(:override) { build(:rate_override, billing_interval_count: 1, billing_interval_unit: "week") }
      let(:phases) do
        [Billing::Phase.new(code: "intro", billing_interval_cycle_count: 2, rate_override: override), Billing::Phase.default]
      end
      let(:at) { zone.parse("2026-01-08") }

      it "persists the second intro cycle with its global index" do
        expect(cycle.phase.code).to eq("intro")
        expect(result.billing_cycle).to have_attributes(
          cycle_index: 1, started_at: Time.utc(2026, 1, 8), ended_at: Time.utc(2026, 1, 15)
        )
      end

      context "when the default phase begins" do
        let(:at) { zone.parse("2026-01-15") }

        it "keeps counting cycles across the change of cadence" do
          expect(cycle.phase.code).to be_nil
          expect(result.billing_cycle).to have_attributes(
            cycle_index: 2, started_at: Time.utc(2026, 1, 15), ended_at: Time.utc(2026, 2, 15)
          )
        end
      end
    end

    context "when the index already identifies a different calendar" do
      let!(:existing) do
        create(:billing_cycle, organization: contract_rate_card.organization, contract_rate_card:,
          ended_at: Time.utc(2026, 1, 8))
      end

      it "reports a conflict without rewriting the period" do
        expect { result }.not_to change { existing.reload.attributes }
        expect(result.error.messages).to eq(billing_cycle: ["calendar_conflict"])
        expect(result.billing_cycle).to be_nil
      end
    end

    context "when another index already identifies the same start" do
      let!(:existing) do
        create(:billing_cycle, organization: contract_rate_card.organization, contract_rate_card:, cycle_index: 1)
      end

      it "reports a conflict without inserting a duplicate period" do
        expect { result }.not_to change { [BillingCycle.count, existing.reload.attributes] }
        expect(result.error.messages).to eq(billing_cycle: ["calendar_conflict"])
        expect(result.billing_cycle).to be_nil
      end
    end
  end
end
