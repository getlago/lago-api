# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::StripeCustomer, type: :model do
  subject(:stripe_customer) { described_class.new(attributes) }

  let(:attributes) {}

  describe 'payment_method_id' do
    it 'assigns and retrieve a payment method id' do
      stripe_customer.payment_method_id = 'foo_bar'
      expect(stripe_customer.payment_method_id).to eq('foo_bar')
    end
  end
end
