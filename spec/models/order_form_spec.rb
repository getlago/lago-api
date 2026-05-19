# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForm do
  subject(:order_form) { build(:order_form, quote_version: nil) }

  describe "enums" do
    it do
      expect(order_form).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(generated: "generated", signed: "signed", expired: "expired", voided: "voided")
        .with_default(:generated)

      expect(order_form).to define_enum_for(:void_reason)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(manual: "manual", expired: "expired", invalid: "invalid")
        .without_instance_methods
    end
  end

  describe "associations" do
    it do
      expect(order_form).to belong_to(:organization)
      expect(order_form).to belong_to(:customer)
      expect(order_form).to belong_to(:quote_version)
      expect(order_form).to belong_to(:signed_by_user).class_name("User").optional
      expect(order_form).to have_one(:quote).through(:quote_version)
    end
  end

  describe "validations" do
    it do
      expect(order_form).to validate_presence_of(:billing_snapshot)
    end

    describe "number presence" do
      it "is required when the callback cannot derive it" do
        expect(order_form).not_to be_valid
        expect(order_form.errors[:number]).to be_present
      end
    end
  end

  describe "#ensure_number" do
    let(:quote) { create(:quote) }
    let(:quote_version) { create(:quote_version, quote:, organization: quote.organization) }

    it "derives the number from the parent quote on save" do
      order_form = build(:order_form, quote_version:, number: nil)

      expect { order_form.save! }
        .to change(order_form, :number)
        .from(nil)
        .to(quote.number.sub("QT", "OF"))
    end

    context "when the number is already set" do
      it "does not overwrite it" do
        order_form = build(:order_form, quote_version:, number: "OF-CUSTOM")

        expect { order_form.save! }.not_to change(order_form, :number).from("OF-CUSTOM")
      end
    end
  end
end
