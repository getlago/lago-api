# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Anrok::CreateService, type: :service do
  let(:service) { described_class.new(membership.user) }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '#call' do
    subject(:service_call) { service.call(**create_args) }

    let(:name) { 'Anrok 1' }

    let(:create_args) do
      {
        name:,
        code: 'anrok1',
        organization_id: organization.id,
        api_key: '123456789'
      }
    end

    context 'without premium license' do
      it 'does not create an integration' do
        expect { service_call }.not_to change(Integrations::AnrokIntegration, :count)
      end

      it 'returns an error' do
        result = service_call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        end
      end
    end

    context 'with premium license' do
      around { |test| lago_premium!(&test) }

      context 'when anrok premium integration is not present' do
        it 'returns an error' do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          end
        end
      end

      context 'when anrok premium integration is present' do
        before do
          organization.update!(premium_integrations: ['anrok'])
        end

        context 'without validation errors' do
          it 'creates an integration' do
            expect { service_call }.to change(Integrations::AnrokIntegration, :count).by(1)

            integration = Integrations::AnrokIntegration.order(:created_at).last
            expect(integration.name).to eq(name)
          end

          it 'returns an integration in result object' do
            result = service_call

            expect(result.integration).to be_a(Integrations::AnrokIntegration)
          end
        end

        context 'with validation error' do
          let(:name) { nil }

          it 'returns an error' do
            result = service_call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
            end
          end
        end
      end
    end
  end
end
