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
end
