# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::StripeProvider, type: :model do
  subject(:stripe_provider) { described_class.new(attributes) }

  it { is_expected.to validate_length_of(:success_redirect_url).is_at_most(1024).allow_nil }

  let(:attributes) {}

  describe 'secret_key' do
    it 'assigns and retrieve a secret key' do
      stripe_provider.secret_key = 'foo_bar'
      expect(stripe_provider.secret_key).to eq('foo_bar')
    end
  end

  describe 'create_customers' do
    it 'assigns and retrieve a setting' do
      stripe_provider.create_customers = true
      expect(stripe_provider.create_customers).to be_truthy
    end
  end

  describe 'webhook_id' do
    it 'assigns and retrieve a setting' do
      stripe_provider.webhook_id = 'webhook_id'
      expect(stripe_provider.webhook_id).to eq('webhook_id')
    end
  end

  describe 'webhook_secret' do
    it 'assigns and retrieve a setting' do
      stripe_provider.webhook_secret = 'secret'
      expect(stripe_provider.webhook_secret).to eq('secret')
    end
  end

  describe '#success_redirect_url' do
    let(:success_redirect_url) { Faker::Internet.url }

    before { stripe_provider.success_redirect_url = success_redirect_url }

    it 'returns the url' do
      expect(stripe_provider.success_redirect_url).to eq success_redirect_url
    end
  end
end
