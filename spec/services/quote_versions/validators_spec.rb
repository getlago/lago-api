# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators do
  describe ".for" do
    subject(:validator) { described_class.for(result, quote_version:, scope: :update) }

    let(:result) { BaseService::Result.new }
    let(:quote) { build(:quote, order_type:) }
    let(:quote_version) { build(:quote_version, quote:) }

    context "when the quote is one_off" do
      let(:order_type) { :one_off }

      it "returns a one_off validator" do
        expect(validator).to be_a(QuoteVersions::Validators::OneOffService)
      end
    end

    context "when the quote is subscription_creation" do
      let(:order_type) { :subscription_creation }

      it "returns no validator" do
        expect(validator).to be_nil
      end
    end

    context "when the quote is subscription_amendment" do
      let(:order_type) { :subscription_amendment }

      it "returns no validator" do
        expect(validator).to be_nil
      end
    end
  end
end
