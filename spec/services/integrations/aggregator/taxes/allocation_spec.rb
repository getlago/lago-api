# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Allocation do
  subject(:allocated) { described_class.call(total, weights) }

  describe ".by_group" do
    subject(:allocated) { described_class.by_group(5, groups) }

    let(:booked) { [2, 3] }
    let(:groups) do
      booked.map do |amount|
        [build(:fee_applied_tax, amount_cents: amount, precise_amount_cents: 2.5)]
      end
    end

    it "preserves booked amounts even when precise shares differ" do
      expect(allocated).to eq([2, 3])
    end

    context "when only one group has rounded to zero" do
      let(:booked) { [0, 2] }

      it { is_expected.to eq([0, 5]) }
    end

    context "when every group has rounded to zero" do
      let(:booked) { [0, 0] }

      it { is_expected.to eq([3, 2]) }
    end
  end

  describe ".precise" do
    subject(:shares) { described_class.precise(total, weights) }

    let(:total) { 7 }
    let(:weights) { [3, 7] }

    it "retains fractional cents" do
      expect(shares).to eq([2.1.to_d, 4.9.to_d])
      expect(shares).to all(be_a(BigDecimal))
    end

    context "with decimal weights and a decimal total" do
      let(:total) { 0.3.to_d }
      let(:weights) { [0.1.to_d, 0.2.to_d] }

      it { is_expected.to eq([0.1.to_d, 0.2.to_d]) }
    end

    context "with a negative total" do
      let(:total) { -7 }

      it { is_expected.to eq([-2.1.to_d, -4.9.to_d]) }
    end

    context "without a total" do
      let(:total) { nil }

      it { is_expected.to eq([0.to_d, 0.to_d]) }
    end

    context "when the weights carry no value" do
      let(:weights) { [0, 0] }

      it { is_expected.to eq([0.to_d, 0.to_d]) }
    end
  end

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
