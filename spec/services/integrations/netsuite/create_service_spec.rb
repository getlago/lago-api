# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Netsuite::CreateService, type: :service do
  let(:service) { described_class.new(membership.user) }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe '#call' do
    subject(:service_call) { service.call(**create_args) }

    let(:name) { 'Netsuite 1' }
    let(:script_endpoint_url) { Faker::Internet.url }

    let(:create_args) do
      {
        name:,
        code: 'netsuite1',
        organization_id: organization.id,
        connection_id: 'conn1',
        client_id: 'cl1',
        client_secret: 'secret',
        account_id: 'acc1',
        script_endpoint_url:
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
        before do
          organization.update!(premium_integrations: ['netsuite'])
          allow(Integrations::Aggregator::SendRestletEndpointJob).to receive(:perform_later)
          allow(Integrations::Aggregator::PerformSyncJob).to receive(:perform_later)
          allow(Integrations::Aggregator::FetchItemsJob).to receive(:perform_later)
          allow(Integrations::Aggregator::FetchTaxItemsJob).to receive(:perform_later)
        end

        context 'without validation errors' do
          it 'creates an integration' do
            expect { service_call }.to change(Integrations::NetsuiteIntegration, :count).by(1)

            integration = Integrations::NetsuiteIntegration.order(:created_at).last
            expect(integration.name).to eq(name)
            expect(integration.script_endpoint_url).to eq(script_endpoint_url)
          end

          it 'returns an integration in result object' do
            result = service_call

            expect(result.integration).to be_a(Integrations::NetsuiteIntegration)
          end

          it 'calls Integrations::Aggregator::SendRestletEndpointJob' do
            service_call

            integration = Integrations::NetsuiteIntegration.order(:created_at).last
            expect(Integrations::Aggregator::SendRestletEndpointJob).to have_received(:perform_later).with(integration:)
          end

          it 'calls Integrations::Aggregator::PerformSyncJob' do
            expect { service_call }.to have_enqueued_job(Integrations::Aggregator::PerformSyncJob)
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
