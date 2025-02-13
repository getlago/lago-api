# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::AdyenCustomer, type: :model do
  describe "#payment_method_id" do
    subject(:customer_payment_method_id) { adyen_customer.payment_method_id }

    let(:adyen_customer) { FactoryBot.build_stubbed(:adyen_customer) }
    let(:payment_method_id) { SecureRandom.uuid }

    before { adyen_customer.payment_method_id = payment_method_id }

    it "returns the payment method id" do
      expect(customer_payment_method_id).to eq payment_method_id
    end
  end
end
