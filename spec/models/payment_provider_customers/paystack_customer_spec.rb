# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::PaystackCustomer do
  subject(:paystack_customer) { build(:paystack_customer) }

  describe "Associations" do
    it { is_expected.to belong_to(:customer) }
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to belong_to(:payment_provider).optional }
    it { is_expected.to have_many(:payment_methods) }
    it { is_expected.to have_many(:refunds) }
  end

  describe "Validations" do
    it "allows one active Paystack customer per Lago customer" do
      existing_customer = create(:paystack_customer)
      duplicate_customer = build(:paystack_customer, customer: existing_customer.customer)

      expect(duplicate_customer).not_to be_valid
      expect(duplicate_customer.errors.where(:customer_id, :taken)).to be_present
    end
  end

  describe "#provider_payment_methods" do
    it "returns card as the reusable payment method" do
      expect(paystack_customer.provider_payment_methods).to eq(["card"])
    end
  end
end
