# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::StripeProvider, type: :model do
  subject(:stripe_provider) { described_class.new(attributes) }

  let(:attributes) {}

  describe 'public_key' do
    it 'assigns and retrieve a secret key' do
      stripe_provider.public_key = 'foo_bar'
      expect(stripe_provider.public_key).to eq('foo_bar')
    end
  end

  describe 'secret_key' do
    it 'assigns and retrieve a secret key' do
      stripe_provider.secret_key = 'foo_bar'
      expect(stripe_provider.secret_key).to eq('foo_bar')
    end
  end
end
