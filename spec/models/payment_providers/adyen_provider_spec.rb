# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::AdyenProvider, type: :model do
  subject(:provider) { FactoryBot.build_stubbed(:adyen_provider) }

  describe '#api_key' do
    let(:api_key) { SecureRandom.uuid }

    before { provider.api_key = api_key }

    it 'returns the api key' do
      expect(provider.api_key).to eq api_key
    end
  end

  describe '#merchant_account' do
    let(:merchant_account) { 'TestECOM' }

    before { provider.merchant_account = merchant_account }

    it 'returns the merchant account' do
      expect(provider.merchant_account).to eq merchant_account
    end
  end

  describe '#live_prefix' do
    let(:live_prefix) { Faker::Internet.domain_word }

    before { provider.live_prefix = live_prefix }

    it 'returns the live prefix' do
      expect(provider.live_prefix).to eq live_prefix
    end
  end

  describe '#hmac_key' do
    let(:hmac_key) { SecureRandom.uuid }

    before { provider.hmac_key = hmac_key }

    it 'returns the hmac key' do
      expect(provider.hmac_key).to eq hmac_key
    end
  end
end
