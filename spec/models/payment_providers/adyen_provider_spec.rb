# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::AdyenProvider, type: :model do
  let(:provider) { FactoryBot.build_stubbed(:adyen_provider) }

  describe '#api_key' do
    subject { provider.api_key }

    let(:api_key) { SecureRandom.uuid }

    before { provider.api_key = api_key }

    it 'returns the api key' do
      expect(subject).to eq api_key
    end
  end

  describe '#merchant_account' do
    subject { provider.merchant_account }

    let(:merchant_account) { 'TestECOM' }

    before { provider.merchant_account = merchant_account }

    it 'returns the merchant account' do
      expect(subject).to eq merchant_account
    end
  end

  describe '#live_prefix' do
    subject { provider.live_prefix }

    let(:live_prefix) { Faker::Internet.domain_word }

    before { provider.live_prefix = live_prefix }

    it 'returns the live prefix' do
      expect(subject).to eq live_prefix
    end
  end

  describe '#hmac_key' do
    subject { provider.hmac_key }

    let(:hmac_key) { SecureRandom.uuid }

    before { provider.hmac_key = hmac_key }

    it 'returns the hmac key' do
      expect(subject).to eq hmac_key
    end
  end
end
