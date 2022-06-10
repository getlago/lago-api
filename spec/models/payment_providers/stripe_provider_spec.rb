# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::StripeProvider, type: :model do
  subject(:stripe_provider) { described_class.new(attributes) }

  let(:attributes) {}

  describe 'secret_key' do
    it 'assigns and retrieve a secret key' do
      stripe_provider.secret_key = 'foo_bar'
      expect(stripe_provider.secret_key).to eq('foo_bar')
    end
  end

  describe 'create_customers' do
    it 'assigns and settings' do
      stripe_provider.create_customers = true
      expect(stripe_provider.create_customers).to be_truthy
    end
  end

  describe 'send_zero_amount_invoice' do
    it 'assigns and settings' do
      stripe_provider.send_zero_amount_invoice = true
      expect(stripe_provider.send_zero_amount_invoice).to be_truthy
    end
  end
end
