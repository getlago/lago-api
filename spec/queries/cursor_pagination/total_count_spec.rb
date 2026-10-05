# frozen_string_literal: true

require "rails_helper"

RSpec.describe CursorPagination::TotalCount do
  subject(:total_count) { described_class.call(relation) }

  let(:organization) { create(:organization) }
  let(:relation) { Product.where(organization:).includes(:product_category).order(:name).limit(1) }
  let(:counter) { Yabeda.api_pagination.total_counts_total }
  # Sleeps once per count, so that the count outlasts a short statement timeout.
  let(:slow_relation) { Product.where(organization:).where("(SELECT pg_sleep(0.3)) IS NULL") }

  before do
    create_list(:product, 3, organization:)
    allow(counter).to receive(:increment)
  end

  context "when the list is below the cap" do
    it "returns the exact count, ignoring order and limit" do
      expect(total_count).to eq(described_class::Result.new(value: 3, outcome: :exact))
      expect(total_count.estimated).to be(false)
      expect(counter).to have_received(:increment).with({table: "products", outcome: :exact})
    end
  end

  context "when the list lands exactly on the cap" do
    before { stub_const("#{described_class}::MAX_COUNTED_RECORDS", 3) }

    it "returns the exact count" do
      expect(total_count).to eq(described_class::Result.new(value: 3, outcome: :exact))
    end
  end

  context "when the list is beyond the cap" do
    before { stub_const("#{described_class}::MAX_COUNTED_RECORDS", 1) }

    it "returns an estimate, never below the cap" do
      expect(total_count.outcome).to eq(:capped)
      expect(total_count.estimated).to be(true)
      expect(total_count.value).to be >= 2
      expect(counter).to have_received(:increment).with({table: "products", outcome: :capped})
    end
  end

  context "when the count times out" do
    let(:relation) { slow_relation }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_API_TOTAL_COUNT_TIMEOUT_MS").and_return("10")
    end

    it "returns the planner's estimate" do
      expect(total_count.outcome).to eq(:timed_out)
      expect(total_count.value).to be_a(Integer)
      expect(counter).to have_received(:increment).with({table: "products", outcome: :timed_out})
    end
  end

  context "when the connection has a stricter statement timeout" do
    let(:relation) { slow_relation }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_API_TOTAL_COUNT_TIMEOUT_MS").and_return("5000")
      # Scoped to the transaction wrapping the example.
      ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = 100")
    end

    it "keeps the stricter timeout" do
      expect(total_count.outcome).to eq(:timed_out)
    end
  end

  context "when the connection has a looser statement timeout" do
    let(:relation) { slow_relation }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_API_TOTAL_COUNT_TIMEOUT_MS").and_return("100")
      ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = 5000")
    end

    it "applies the count timeout" do
      expect(total_count.outcome).to eq(:timed_out)
    end
  end
end
