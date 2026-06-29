# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::BaseService do
  subject(:validator) { described_class.new(result, quote_version:, scope: :approve) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }

  context "when the quote is one_off" do
    let(:quote) { create(:quote, organization:, order_type: :one_off) }
    let(:quote_version) { build(:quote_version, quote:, organization:, currency: "EUR", billing_items: {}) }

    it "delegates to OneOffService and applies its rules" do
      expect(validator).not_to be_valid
      expect(result.error.messages[:add_ons]).to eq(["add_ons_required"])
    end
  end

  context "when the order type has no validator yet" do
    let(:quote) { create(:quote, organization:, order_type: :subscription_creation) }
    let(:quote_version) { build(:quote_version, quote:, organization:) }

    it "is a no-op and returns true" do
      expect(validator).to be_valid
      expect(result.error).to be_nil
    end
  end
end
