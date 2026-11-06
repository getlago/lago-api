# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots do
  let(:organization) { build_stubbed(:organization) }

  describe ".read_enabled?" do
    it "follows the persisted_recurring_values feature flag" do
      expect(described_class.read_enabled?(organization)).to be(false)

      organization.feature_flags = ["persisted_recurring_values"]
      expect(described_class.read_enabled?(organization)).to be(true)
    end

    context "when the read is forced" do
      it "returns the forced value whatever the flag says" do
        expect(described_class.with_forced_read(true) { described_class.read_enabled?(organization) }).to be(true)

        organization.feature_flags = ["persisted_recurring_values"]
        expect(described_class.with_forced_read(false) { described_class.read_enabled?(organization) }).to be(false)
        expect(described_class.read_enabled?(organization)).to be(true)
      end
    end
  end

  describe ".with_forced_read" do
    it "refuses to be nested" do
      expect { described_class.with_forced_read(true) { described_class.with_forced_read(false) {} } }
        .to raise_error(RuntimeError, /already forced/)
    end

    it "releases the forced read when the block raises" do
      expect { described_class.with_forced_read(true) { raise "boom" } }.to raise_error("boom")
      expect(described_class.read_enabled?(organization)).to be(false)
    end
  end
end
