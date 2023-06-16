# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookEndpoint, type: :model do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:webhooks).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:webhook_url) }

  describe 'validations' do
    subject(:webhook_endpoint) { FactoryBot.build(:webhook_endpoint) }

    context 'when http webhook url is valid' do
      before { webhook_endpoint.webhook_url = 'http://foo.bar' }

      it 'is valid' do
        expect(webhook_endpoint).to be_valid
      end
    end

    context 'when https webhook url is valid' do
      before { webhook_endpoint.webhook_url = 'https://foo.bar' }

      it 'is valid' do
        expect(webhook_endpoint).to be_valid
      end
    end

    context 'when webhook url is invalid' do
      before { webhook_endpoint.webhook_url = 'foobar' }

      it 'is invalid' do
        expect(webhook_endpoint).not_to be_valid
      end
    end
  end
end
