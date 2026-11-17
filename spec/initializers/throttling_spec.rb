# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Throttling initializer" do # rubocop:disable RSpec/DescribeClass
  def limits_for(provider)
    Throttling.limits[provider].to_hash.deep_symbolize_keys
  end

  it "registers exactly the six provider entries" do
    expect(Throttling.limits.keys).to match_array(%w[hubspot xero netsuite anrok avalara quickbooks])
  end

  it "keeps the existing provider limits unchanged" do
    expect(limits_for(:hubspot)).to eq(tensecondly: {limit: 110, period: 10})
    expect(limits_for(:xero)).to eq(minutely: {limit: 60, period: 60}, daily: {limit: 5000, period: 86400})
    expect(limits_for(:netsuite)).to eq(secondly: {limit: 10, period: 1})
    expect(limits_for(:anrok)).to eq(secondly: {limit: 9, period: 1})
    expect(limits_for(:avalara)).to eq(secondly: {limit: 10, period: 1})
  end

  it "limits QuickBooks to a single window of 150 per 60 seconds" do
    expect(limits_for(:quickbooks)).to eq(minutely: {limit: 150, period: 60})
  end

  it "keeps the shared concurrency limit at a single limit of 5" do
    strategy = Sidekiq::Throttled::Registry.get(:concurrency_limit)

    expect(strategy.concurrency.map(&:limit)).to eq([5])
    expect(strategy.threshold.to_a).to be_empty
  end

  context "with a real counter store" do
    let(:check_value) { "placeholder-throttle-key" }

    before do
      allow(Throttling).to receive(:storage).and_return(ActiveSupport::Cache::MemoryStore.new)
      travel_to(Time.zone.parse("2026-01-05 10:00:00"))
    end

    def check_quickbooks
      Throttling.for(:quickbooks).check(:client, check_value)
    end

    it "allows 150 QuickBooks calls in one minute and refuses the 151st" do
      results = Array.new(150) { check_quickbooks }

      expect(results).to all(be(true))
      expect(check_quickbooks).to be(false)
    end

    it "still refuses QuickBooks calls 59 seconds into the same minute" do
      151.times { check_quickbooks }

      travel(59.seconds)

      expect(check_quickbooks).to be(false)
    end

    it "allows QuickBooks calls again in the next minute" do
      151.times { check_quickbooks }

      travel(60.seconds)

      expect(check_quickbooks).to be(true)
    end
  end
end
