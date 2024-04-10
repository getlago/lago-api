# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Okta::UpdateService, type: :service do
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  describe '#call' do
    subject(:service_call) { described_class.call(integration:, params: update_args) }

    before { integration }

    let(:name) { 'Netsuite 1' }

    let(:update_args) do
      {
        name:,
        code: 'netsuite1',
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
          it 'updates an integration' do
            service_call

            integration = Integrations::NetsuiteIntegration.order(:updated_at).last
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
