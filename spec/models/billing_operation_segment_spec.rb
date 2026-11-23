# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperationSegment do
  subject(:segment) do
    described_class.new(
      organization:, billing_operation: operation, rate_card_rate: rate, position: 0,
      started_at: Time.utc(2026, 11, 1), ended_at: Time.utc(2026, 12, 1), proration_ratio: 1
    )
  end

  let(:organization) { create(:organization) }
  let(:operation) { create(:billing_operation, organization:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card: operation.contract_rate_card.rate_card) }

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
      expect(segment).to validate_presence_of(:proration_ratio)
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
end
