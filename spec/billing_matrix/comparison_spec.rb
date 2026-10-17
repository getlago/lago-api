# frozen_string_literal: true

require "spec_helper"
require_relative "../../billing_matrix/runner/comparison"

RSpec.describe BillingMatrix::Comparison do
  it "reports a one-cent difference and a missing field" do
    result = described_class.call(expected: {invoice: {total_amount_cents: 100, taxes_amount_cents: 0}},
      observed: {invoice: {total_amount_cents: 99}})
    expect(result.mismatches).to eq([
      {path: "invoice.total_amount_cents", expected: 100, observed: 99},
      {path: "invoice.taxes_amount_cents", expected: 0, observed: nil}
    ])
  end

  it "compares equivalent decimal units and absolute times" do
    result = described_class.call(expected: {units: "1.00", from_date: "2026-03-01T01:00:00+01:00"},
      observed: {units: 1, from_date: "2026-03-01T00:00:00Z"})
    expect(result).to be_match
  end

  it "matches fees by identity regardless of order" do
    fees = [{fee_type: "subscription", amount_cents: 100}, {fee_type: "charge", amount_cents: 200}]
    expect(described_class.call(expected: {fees:}, observed: {fees: fees.reverse})).to be_match
  end

  it "rejects duplicate observed fee identities" do
    fees = [{fee_type: "charge", amount_cents: 100}, {fee_type: "charge", amount_cents: 200}]
    expect { described_class.call(expected: {fees:}, observed: {fees:}) }
      .to raise_error(described_class::AmbiguousFeeIdentity, /share the same identity/)
  end

  it "rejects an expectation matching multiple distinct fees" do
    fees = [{fee_type: "charge", item_code: "a"}, {fee_type: "charge", item_code: "b"}]
    expect { described_class.call(expected: {fees: [{fee_type: "charge"}]}, observed: {fees:}) }
      .to raise_error(described_class::AmbiguousFeeIdentity, /matches 2 observed fees/)
  end
end
