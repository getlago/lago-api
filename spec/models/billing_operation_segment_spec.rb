# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperationSegment do
  subject(:segment) do
    described_class.new(
      organization:, billing_operation: operation, rate_card_rate: rate, position: 0,
      started_at: Time.utc(2026, 11, 1), ended_at: Time.utc(2026, 12, 1), proration_ratio:
    )
  end

  let(:organization) { create(:organization) }
  let(:operation) { create(:billing_operation, organization:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card: operation.contract_rate_card.rate_card) }
  let(:proration_ratio) { 1 }

  describe "associations" do
    it do
      expect(segment).to belong_to(:organization)
      expect(segment).to belong_to(:billing_operation).inverse_of(:segments)
      expect(segment).to belong_to(:rate_card_rate)
      expect(segment).to belong_to(:rate_override).optional
    end
  end

  describe "validations" do
    it "accepts an owned source and half-open coverage" do
      expect(segment).to be_valid
      expect(segment).to validate_presence_of(:started_at)
      expect(segment).to validate_presence_of(:ended_at)
      expect(segment).to validate_presence_of(:proration_ratio)
      expect(segment).to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0)
    end

    context "when the operation belongs to another organization" do
      let(:operation) { create(:billing_operation) }

      it "rejects the operation" do
        expect(segment).not_to be_valid
        expect(segment.errors.of_kind?(:billing_operation, :invalid)).to be(true)
      end
    end

    context "when the rate belongs to another card" do
      let(:rate) { create(:rate_card_rate, organization:) }

      it { expect(segment).not_to be_valid }
    end

    context "when the override belongs to another organization" do
      before { segment.rate_override = create(:rate_override) }

      it { expect(segment).not_to be_valid }
    end

    context "when the end does not follow the start" do
      before { segment.ended_at = segment.started_at }

      it { expect(segment).not_to be_valid }
    end
  end

  describe "check constraints" do
    subject(:insert) { segment.save!(validate: false) }

    %w[0 0.5 1].each do |ratio|
      context "with a proration ratio of #{ratio}" do
        let(:proration_ratio) { BigDecimal(ratio) }

        it "persists the ratio" do
          insert

          expect(segment.reload.proration_ratio).to eq(proration_ratio)
        end
      end
    end

    %w[-0.0000000001 1.0000000001].each do |ratio|
      context "with an out-of-bounds proration ratio of #{ratio}" do
        let(:proration_ratio) { BigDecimal(ratio) }

        it "rejects the insert even without model validation" do
          expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*billing_operation_segments_proration_ratio_bounds/)
        end
      end
    end
  end
end
