# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ErrorDetails::CreateService, type: :service do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:integration) { create(:anrok_integration, organization:) }
  let(:owner) { create(:invoice, organization:, customer:) }

  describe '#call' do
    subject(:service_call) { described_class.call(params:, integration:, owner:) }

    let(:params) do
      {
        details: {'error_code' => 'taxDateTooFarInFuture'}
      }
    end

    context 'when all both - owner and integration are provided' do
      it 'creates an integration_error_detail' do
        expect { service_call }.to change(ErrorDetail, :count).by(1)
      end

      it 'returns created integration_error_detail' do
        result = service_call

        aggregate_failures do
          expect(result).to be_success
          expect(result.error_details.owner_id).to eq(owner.id)
          expect(result.error_details.owner_type).to eq(owner.class.to_s)
          expect(result.error_details.integration_id).to eq(integration.id)
          expect(result.error_details.integration.class.to_s).to eq(integration.class.to_s)
          expect(result.error_details.details).to eq(params[:details])
        end
      end
    end

    context 'when no integration association is provided' do
      subject(:service_call) { described_class.call(params:, owner:) }

      it 'creates an integration_error_detail' do
        expect { service_call }.to change(ErrorDetail, :count).by(1)
      end

      it 'returns created integration_error_detail' do
        result = service_call

        aggregate_failures do
          expect(result).to be_success
          expect(result.error_details.owner_id).to eq(owner.id)
          expect(result.error_details.owner_type).to eq(owner.class.to_s)
          expect(result.error_details.integration_id).to eq(nil)
          expect(result.error_details.integration_type).to eq(nil)
          expect(result.error_details.details).to eq(params[:details])
        end
      end
    end

    context 'when no owner is provided' do
      subject(:service_call) { described_class.call(params:, integration:, owner: nil) }

      it 'does not create an integration_error_detail' do
        expect { service_call }.to change(ErrorDetail, :count).by(0)
      end

      it 'returns created integration_error_detail' do
        result = service_call
        aggregate_failures do
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to include('owner_not_found')
        end
      end
    end
  end
end
