# frozen_string_literal: true

require "spec_helper"
require_relative "../../billing_matrix/runner/row"
require_relative "../../billing_matrix/runner/results"

RSpec.describe BillingMatrix::Results do
  let(:results) { described_class.new }
  let(:canary) { BillingMatrix::Row.new({"id" => "canary/example", "area" => "canary", "canary" => {"mechanism" => "cents"}}, source: "example.yml") }

  it "preserves finding IDs in serialized results" do
    row = BillingMatrix::Row.new({"id" => "smoke/pinned", "area" => "smoke", "pins" => %w[F69 BIL-537]}, source: "example.yml")
    results.record(row:, verdict: :failed, duration_ms: 0)
    results.record(row: canary, verdict: :failed, duration_ms: 0)

    payload = JSON.parse(JSON.generate(results.to_h))
    expect(payload.fetch("rows").map { it.fetch("pins") }).to eq([%w[F69 BIL-537], []])
  end

  it "does not trust a run without canaries" do
    expect(results).not_to be_trustworthy
  end

  it "counts an assertion failure as a proven canary" do
    results.record(row: canary, verdict: :failed, duration_ms: 0)
    expect(results).to be_trustworthy
    expect(results.summary).to eq(passed: 1, failed: 0, errored: 0, canaries_broken: 0, canaries_total: 1, canaries_unproven: 0)
  end

  it "marks a passing canary as broken" do
    results.record(row: canary, verdict: :passed, duration_ms: 0)
    expect(results).not_to be_trustworthy
    expect(results.summary).to eq(passed: 0, failed: 0, errored: 0, canaries_broken: 1, canaries_total: 1, canaries_unproven: 1)
  end

  it "keeps a crashed canary unproven" do
    results.record(row: canary, verdict: :errored, error: "setup failed", duration_ms: 0)
    expect(results).not_to be_trustworthy
    expect(results.summary).to eq(passed: 0, failed: 0, errored: 1, canaries_broken: 0, canaries_total: 1, canaries_unproven: 1)
  end
end
