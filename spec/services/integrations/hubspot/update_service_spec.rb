# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::UpdateService, type: :service do
  let(:integration) { create(:hubspot_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  describe '#call' do
    subject(:service_call) { described_class.call(integration:, params: update_args) }

    before { integration }

    let(:name) { 'Hubspot 1' }
    let(:update_args) do
      {
        name:,
        code: 'hubspot1',
        private_app_token: 'new_token'
      }
    end

    context 'without premium license' do
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

      context 'with hubspot premium integration not present' do
        it 'returns an error' do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          end
        end
      end

      context 'with hubspot premium integration present' do
        before do
          organization.update!(premium_integrations: ['hubspot'])
          allow(Integrations::Aggregator::SendPrivateAppTokenJob).to receive(:perform_later)
        end

        context 'without validation errors' do
          it 'updates an integration' do
            service_call

            integration = Integrations::HubspotIntegration.order(:updated_at).last
            expect(integration.name).to eq(name)
            expect(integration.private_app_token).to eq(update_args[:private_app_token])
          end

          it 'returns an integration in result object' do
            result = service_call

            expect(result.integration).to be_a(Integrations::HubspotIntegration)
          end

          it 'calls Integrations::Aggregator::SendPrivateAppTokenJob' do
            service_call

            expect(Integrations::Aggregator::SendPrivateAppTokenJob).to have_received(:perform_later).with(integration:)
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
