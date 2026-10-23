# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots do
  describe ".read_enabled?" do
    it "reads the snapshots" do
      expect(described_class.read_enabled?).to be(true)
    end

    context "when the read is forced" do
      it "returns the forced value" do
        expect(described_class.with_forced_read(true) { described_class.read_enabled? }).to be(true)
        expect(described_class.with_forced_read(false) { described_class.read_enabled? }).to be(false)
      end
    end
  end

  describe ".with_forced_read" do
    it "refuses to be nested" do
      expect { described_class.with_forced_read(true) { described_class.with_forced_read(false) {} } }
        .to raise_error(RuntimeError, /already forced/)
    end

    it "releases the forced read when the block raises" do
      expect { described_class.with_forced_read(false) { raise "boom" } }.to raise_error("boom")
      expect(described_class.read_enabled?).to be(true)
    end
  end
end
