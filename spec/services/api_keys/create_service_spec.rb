# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiKeys::CreateService, type: :service do
  describe '#call' do
    subject(:service_result) { described_class.call(params) }

    let!(:params) do
      {
        organization_id: create(:organization).id,
        name: Faker::Lorem.words.join(' ')
      }
    end

    context 'with premium organization' do
      around { |test| lago_premium!(&test) }

      it 'creates a new API key' do
        expect { service_result }.to change(ApiKey, :count).by(1)
      end

      it 'sends an API key created email' do
        expect { service_result }
          .to have_enqueued_mail(ApiKeyMailer, :created)
          .with(hash_including(params: {api_key: instance_of(ApiKey)}))
      end
    end

    context 'with free organization' do
      it 'does not create an API key' do
        expect { service_result }.not_to change(ApiKey, :count)
      end

      it 'returns an error' do
        aggregate_failures do
          expect(service_result).not_to be_success
          expect(service_result.error).to be_a(BaseService::ForbiddenFailure)
        end
      end
    end
  end
end
