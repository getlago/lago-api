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
    
    let(:merchant_account) { "TestECOM" }

    before { provider.merchant_account = merchant_account }

    it 'returns the merchant account' do
      expect(subject).to eq merchant_account
    end
  end
end
