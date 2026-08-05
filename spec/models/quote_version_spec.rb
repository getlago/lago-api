# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersion do
  subject(:quote_version) { create(:quote_version) }

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .with_values(draft: "draft", approved: "approved", voided: "voided")
        .with_default(:draft)
        .validating(allowing_nil: false)

      expect(subject).to define_enum_for(:void_reason)
        .backed_by_column_of_type(:enum)
        .with_values(
          manual: "manual",
          superseded: "superseded",
          cascade_of_expired: "cascade_of_expired",
          cascade_of_voided: "cascade_of_voided"
        )
        .without_instance_methods
        .validating(allowing_nil: true)
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:quote)
      expect(subject).to have_one(:order_form)
    end
  end

  describe "validations" do
    it "is valid by default" do
      expect(build(:quote_version)).to be_valid
    end

    describe "void_reason and voided_at" do
      it "are required when status is voided" do
        quote_version = build(:quote_version, status: :voided, void_reason: nil, voided_at: nil)
        expect(quote_version).not_to be_valid

        quote_version.void_reason = :manual
        quote_version.voided_at = Time.current
        expect(quote_version).to be_valid
      end
    end

    describe "approved_at" do
      it "is required when status is approved" do
        quote_version = build(:quote_version, status: :approved, approved_at: nil)
        expect(quote_version).not_to be_valid
      end

      it "is allowed to be nil when status is draft" do
        quote_version = build(:quote_version, status: :draft, approved_at: nil)
        expect(quote_version).to be_valid
      end
    end
  end

  describe "sequencing" do
    it "assigns sequential ids per quote" do
      quote = create(:quote)
      v1 = create(:quote_version, :voided, quote:, organization: quote.organization, sequential_id: nil)
      v2 = create(:quote_version, quote:, organization: quote.organization, sequential_id: nil)
      expect([v1.sequential_id, v2.sequential_id]).to eq([1, 2])
    end
  end

  describe "#version" do
    it "is an alias for sequential_id" do
      quote_version = build(:quote_version, sequential_id: 42)
      expect(quote_version.version).to eq(42)
    end
  end
end
