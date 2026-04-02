# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForm do
  subject(:order_form) { build(:order_form) }

  describe "enums" do
    it do
      expect(order_form).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(generated: "generated", signed: "signed", expired: "expired", voided: "voided")
        .with_default(:generated)

      expect(order_form).to define_enum_for(:void_reason)
        .validating(allowing_nil: true)
        .with_values(manual: 0, expired: 1, invalid: 2)
        .without_instance_methods
    end
  end

  describe "associations" do
    it do
      expect(order_form).to belong_to(:organization)
      expect(order_form).to belong_to(:customer)
      expect(order_form).to belong_to(:quote)
      expect(order_form).to have_one(:order)
    end
  end

  describe "scopes" do
    describe ".expirable" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:quote) { create(:quote, customer:, organization:) }

      let!(:expired_yesterday) do
        create(:order_form, :expired_yesterday, customer:, organization:, quote:)
      end

      before do
        create(:order_form, :expiring_tomorrow, customer:, organization:, quote: create(:quote, customer:, organization:))
        create(:order_form, customer:, organization:, quote: create(:quote, customer:, organization:), expires_at: nil)
        create(:order_form, :expired, customer:, organization:, quote: create(:quote, customer:, organization:))
        create(:order_form, :voided, customer:, organization:, quote: create(:quote, customer:, organization:))
      end

      it "returns only generated order forms past their expiration date" do
        expect(described_class.expirable).to eq([expired_yesterday])
      end
    end
  end

  describe "validations" do
    it do
      expect(order_form).to validate_presence_of(:billing_snapshot)
    end
  end
end
