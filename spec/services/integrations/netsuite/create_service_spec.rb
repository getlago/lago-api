# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Netsuite::CreateService, type: :service do
  let(:service) { described_class.new(membership.user) }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '#call' do
    subject(:service_call) { service.call(**create_args) }

    let(:name) { 'Netsuite 1' }

    let(:create_args) do
      {
        name:,
        code: 'netsuite1',
        organization_id: organization.id,
        connection_id: 'conn1',
        client_id: 'cl1',
        client_secret: 'secret',
        account_id: 'acc1',
      }
    end

    context 'without premium license' do
      it 'does not create an integration' do
        expect { service_call }.not_to change(Integrations::NetsuiteIntegration, :count)
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

      context 'with netsuite premium integration not present' do
        it 'returns an error' do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          end
        end
      end

      context 'with netsuite premium integration present' do
        before { organization.update!(premium_integrations: ['netsuite']) }

        context 'without validation errors' do
          it 'creates an integration' do
            expect { service_call }.to change(Integrations::NetsuiteIntegration, :count).by(1)

            integration = Integrations::NetsuiteIntegration.order(:created_at).last
            expect(integration.name).to eq(name)
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
