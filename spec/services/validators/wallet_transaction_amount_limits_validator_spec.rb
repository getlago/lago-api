# frozen_string_literal: true

require "rails_helper"

RSpec.describe Validators::WalletTransactionAmountLimitsValidator, type: :validator do
  subject { described_class.new(result, wallet:, credits_amount:, ignore_validation:).valid? }

  let(:result) { BaseService::LegacyResult.new }
  let(:wallet) { create(:wallet, paid_top_up_min_amount_cents:, paid_top_up_max_amount_cents:) }
  let(:paid_top_up_min_amount_cents) { 5_00 }
  let(:paid_top_up_max_amount_cents) { 100_00 }
  let(:credits_amount) { 1 }
  let(:ignore_validation) { false }

  describe "#valid?" do
    context "when  ignore_validation is true" do
      let(:ignore_validation) { true }

      it { is_expected.to be true }
    end

    context "when wallet does not have limits" do
      let(:paid_top_up_min_amount_cents) { nil }
      let(:paid_top_up_max_amount_cents) { nil }

      it { is_expected.to be true }
    end

    context "when credits_amount is blank" do
      let(:credits_amount) { nil } # TODO: HANDLE CREDITS AMOUNT AS STRING

      it { is_expected.to be true }
    end

    context "when credits_amount is less than min amount" do
      let(:credits_amount) { 4.99 }

      it do
        expect(subject).to be false
        expect(result).to be_failure
        expect(result.error.messages[:paid_credits]).to eq(["amount_below_minimum"])
      end
    end

    context "when credits_amount is more than max amount" do
      let(:credits_amount) { 100.1 }

      it do
        expect(subject).to be false
        expect(result).to be_failure
        expect(result.error.messages[:paid_credits]).to eq(["amount_above_maximum"])
      end
    end

    context "when credits_amount is equal to a limit" do
      let(:credits_amount) { 5 }
      let(:paid_top_up_max_amount_cents) { paid_top_up_min_amount_cents }

      it { is_expected.to be true }
    end
  end
end
