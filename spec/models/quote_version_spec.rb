# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersion do
  subject(:quote_version) { create(:quote_version) }

  describe "enums" do
    it "defines enums" do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .with_values(
          {
            draft: "draft",
            approved: "approved",
            voided: "voided"
          }
        )
        .with_default(:draft)
        .validating(allowing_nil: false)

      expect(subject).to define_enum_for(:void_reason)
        .backed_by_column_of_type(:enum)
        .with_values(
          {
            manual: "manual",
            superseded: "superseded",
            cascade_of_expired: "cascade_of_expired",
            cascade_of_voided: "cascade_of_voided"
          }
        )
        .without_instance_methods
        .validating(allowing_nil: true)
    end
  end

  describe "associations" do
    it "has the expected associations" do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:quote)

      # TODO: Uncomment when the order form and order associations are implemented
      # expect(subject).to have_one(:order_form)
      # expect(subject).to have_one(:order).through(:order_form)
    end
  end

  describe "validations" do
    it "requires share_token for draft and approved statuses on update" do
      draft = build(:quote_version, status: :draft, share_token: nil)
      expect(draft.valid?(:update)).to be false

      approved = build(:quote_version, status: :approved, share_token: nil, approved_at: Time.current)
      expect(approved.valid?(:update)).to be false
    end

    it "requires void_reason and voided_at when voided" do
      quote_version = build(:quote_version, status: :voided, void_reason: nil, voided_at: nil)
      expect(quote_version).not_to be_valid

      quote_version.void_reason = :manual
      quote_version.voided_at = Time.current
      expect(quote_version).to be_valid
    end

    it "requires approved_at when approved" do
      quote_version = build(:quote_version, status: :approved, approved_at: nil)
      expect(quote_version).not_to be_valid
    end
  end

  describe "callbacks" do
    describe "ensure_share_token" do
      it "generates a share_token for draft versions" do
        quote_version = create(:quote_version, status: :draft, share_token: nil)
        expect(quote_version.share_token).to be_present
      end

      it "does not generate a share_token for voided versions" do
        quote_version = create(:quote_version, :voided)
        expect(quote_version.share_token).to be_nil
      end
    end
  end
end
