# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::MaterializeService do
  subject(:result) { described_class.call(contract_rate_card:, cycles:) }

  let(:contract_rate_card) { create(:contract_rate_card) }
  let(:cycles) do
    [build(:billing_cycle, cycle_index: 0), build(:billing_cycle, cycle_index: 1,
      started_at: Time.utc(2026, 2, 1), ended_at: Time.utc(2026, 3, 1))]
  end

  it "persists the supplied periods in order" do
    expect { result }.to change(BillingCycle, :count).by(2)
    expect(result).to be_success
    expect(result.billing_cycles.map { |cycle| [cycle.cycle_index, cycle.started_at, cycle.ended_at, cycle.timezone] })
      .to eq([[0, Time.utc(2026, 1, 1), Time.utc(2026, 2, 1), "UTC"],
        [1, Time.utc(2026, 2, 1), Time.utc(2026, 3, 1), "UTC"]])
    expect(result.billing_cycles.map(&:organization_id).uniq).to eq([contract_rate_card.organization_id])
  end

  context "with existing periods" do
    let!(:existing) { create(:billing_cycle, contract_rate_card:, organization: contract_rate_card.organization) }

    it "reuses the original row without rewriting it" do
      expect { result }.not_to change { existing.reload.attributes }
      expect(result.billing_cycles.first).to eq(existing)
      expect(contract_rate_card.billing_cycles.count).to eq(2)
    end
  end

  context "with a conflicting later period" do
    let!(:existing) do
      create(:billing_cycle, contract_rate_card:, organization: contract_rate_card.organization,
        cycle_index: 1, started_at: Time.utc(2026, 2, 1), ended_at: Time.utc(2026, 4, 1))
    end

    it "rejects the conflict and rolls back the earlier insert" do
      expect { result }.not_to change { [BillingCycle.count, existing.reload.attributes] }
      expect(result.error.messages).to eq(billing_cycle: ["calendar_conflict"])
      expect(result.billing_cycles).to be_nil
    end
  end

  context "when two writers materialize the same periods", transaction: false do
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
        described_class.new(contract_rate_card: ContractRateCard.find(contract_rate_card.id), cycles:)
      end
    end

    it "returns the same periods to both writers" do
      expect(results).to all(be_success)
      expect(results.map { |result| result.billing_cycles.map(&:id) }.uniq.size).to eq(1)
      expect(contract_rate_card.billing_cycles.count).to eq(2)
    end
  end
end
