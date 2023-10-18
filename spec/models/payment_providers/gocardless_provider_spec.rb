# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::GocardlessProvider, type: :model do
  subject(:gocardless_provider) { described_class.new(attributes) }

  let(:attributes) {}

  describe 'access_token' do
    it 'assigns and retrieves an access token' do
      gocardless_provider.access_token = 'foo_bar'
      expect(gocardless_provider.access_token).to eq('foo_bar')
    end
  end

  describe '#success_redirect_url' do
    let(:success_redirect_url) { Faker::Internet.url }

    before { gocardless_provider.success_redirect_url = success_redirect_url }

    it 'returns the url' do
      expect(gocardless_provider.success_redirect_url).to eq success_redirect_url
    end
  end
end
