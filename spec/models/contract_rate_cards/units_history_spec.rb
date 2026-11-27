# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::UnitsHistory do
  subject(:history) { described_class.new(terms:, changes:, schedule:) }

  let(:customer) { build(:customer, timezone: "America/New_York") }
  let(:contract) { build(:contract, customer:) }
  let(:card) { build(:contract_rate_card, contract:) }
  let(:initial_term) { build(:contract_rate_card_term, contract_rate_card: card, effective_date: Date.new(2026, 9, 1), units: 8) }
  let(:scheduled_term) do
    build(:contract_rate_card_term, contract_rate_card: card, effective_date: Date.new(2026, 9, 10), units: 5, created_at: Time.utc(2026, 9, 10),
      application_timing: :next_billing_cycle)
  end
  let(:schedule) { instance_double(Billing::RateCards::Schedule, next_segment_start: Time.utc(2026, 10, 1, 4)) }
  let(:terms) { [initial_term, scheduled_term] }
  let(:changed_at) { Time.utc(2026, 9, 16, 12, 30, 0, 123456) }
  let(:changes) { [[changed_at, 10.to_d]] }

  it "uses the original quantity before the exact change and the new quantity from that instant" do
    expect(history.units_at(changed_at - Rational(1, 1_000_000))).to eq(8)
    expect(history.units_at(changed_at)).to eq(10)
    expect(history.units_by_timestamp).to be_frozen
  end

  it "preserves scheduled units at the next customer-local boundary" do
    expect(history.scheduled_term_at(changed_at)).to have_attributes(term: scheduled_term, starts_at: Time.utc(2026, 10, 1, 4))
    expect(history.units_at(Time.utc(2026, 10, 1, 4))).to eq(5)
    expect(history.scheduled_term_at(Time.utc(2026, 10, 1, 4))).to be_nil
  end

  context "when an immediate change has the same instant as a dated term" do
    let(:changes) { [[Time.utc(2026, 10, 1, 4), 7.to_d]] }

    it "uses the immediate quantity once" do
      expect(history.units_at(Time.utc(2026, 10, 1, 4))).to eq(7)
      expect(history.units_by_timestamp.size).to eq(2)
    end
  end
end
