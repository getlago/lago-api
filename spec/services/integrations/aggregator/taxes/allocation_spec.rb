# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Allocation do
  subject(:allocated) { described_class.call(total, weights) }

  describe ".call" do
    context "when the figure divides evenly over the weights" do
      let(:total) { 90 }
      let(:weights) { [10, 10, 10] }

      it { is_expected.to eq([30, 30, 30]) }
    end

    context "when every share rounds the same way" do
      # 100 fees of 8 cents taxed at 20%: each owes 1.6 cents, so rounding each
      # on its own would book 200 cents against the 160 the provider returned.
      let(:total) { 160 }
      let(:weights) { Array.new(100, 8) }

      it "spends the figure the provider returned, exactly" do
        expect(allocated.sum).to eq(160)
      end

      it "keeps every share within a cent of its exact value" do
        expect(allocated.uniq).to match_array([1, 2])
      end

      it "never books a negative share" do
        expect(allocated).to all(be >= 0)
      end
    end

    context "when the figure is smaller than the number of shares" do
      let(:total) { 3 }
      let(:weights) { Array.new(1000, 1) }

      it "gives a cent to as many shares as the figure covers" do
        expect(allocated.sum).to eq(3)
        expect(allocated.count(1)).to eq(3)
        expect(allocated.count(0)).to eq(997)
      end
    end

    context "with uneven weights" do
      let(:total) { 7 }
      let(:weights) { [1.4, 5.2] }

      it { is_expected.to eq([1, 6]) }
    end

    context "when the figure is negative" do
      let(:total) { -160 }
      let(:weights) { Array.new(100, 8) }

      it "spends it exactly" do
        expect(allocated.sum).to eq(-160)
      end

      it "never books a positive share" do
        expect(allocated).to all(be <= 0)
      end
    end

    context "without a figure to allocate" do
      let(:total) { nil }
      let(:weights) { [1, 2] }

      it { is_expected.to eq([0, 0]) }
    end

    context "when the weights carry no value" do
      let(:total) { 10 }
      let(:weights) { [0, 0] }

      it { is_expected.to eq([0, 0]) }
    end
  end
end
