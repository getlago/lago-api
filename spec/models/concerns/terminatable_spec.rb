# frozen_string_literal: true

require "rails_helper"

RSpec.describe Terminatable do
  describe "#terminated_at?" do
    subject(:terminated_at?) { record.terminated_at?(timestamp) }

    let(:record) { build(:subscription, status:, terminated_at:) }
    let(:status) { :terminated }
    let(:terminated_at) { Time.zone.parse("2026-03-15 12:00:00") }
    let(:timestamp) { Time.zone.parse("2026-03-15 12:00:01") }

    it "returns true when the record was terminated at or before the timestamp" do
      expect(terminated_at?).to eq(true)
    end

    context "when the record is not terminated" do
      let(:status) { :active }

      it { expect(terminated_at?).to eq(false) }
    end

    context "when terminated_at is blank" do
      let(:terminated_at) { nil }

      it { expect(terminated_at?).to eq(false) }
    end

    context "when timestamp is blank" do
      let(:timestamp) { nil }

      it { expect(terminated_at?).to eq(false) }
    end

    context "when timestamp is before terminated_at" do
      let(:timestamp) { Time.zone.parse("2026-03-15 11:59:59") }

      it { expect(terminated_at?).to eq(false) }
    end

    context "when timestamp is a date" do
      let(:terminated_at) { Time.zone.parse("2026-03-15 00:00:00") }
      let(:timestamp) { Date.parse("2026-03-15") }

      it { expect(terminated_at?).to eq(true) }
    end

    context "when timestamp is an integer" do
      let(:timestamp) { Time.zone.parse("2026-03-15 12:00:01").to_i }

      it { expect(terminated_at?).to eq(true) }
    end

    context "with a contract" do
      let(:record) { build(:contract, status:, terminated_at:) }

      it "uses the same predicate" do
        expect(terminated_at?).to eq(true)
      end
    end
  end
end
