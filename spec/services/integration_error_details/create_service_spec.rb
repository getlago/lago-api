# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationErrorDetails::CreateService, type: :service do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:error_producer) { create(:anrok_integration, organization:) }
  let(:owner) { create(:invoice, organization:, customer:) }

  describe '#call' do
    subject(:service_call) { described_class.call(params:, error_producer:, owner:) }

    let(:params) do
      {
        details: {'error_code' => 'taxDateTooFarInFuture'}
      }
    end

    context 'when all required data present' do
      it 'creates an integration_error_detail' do
        expect { service_call }.to change(IntegrationErrorDetail, :count).by(1)
      end

      it 'returns created integration_error_detail' do
        result = service_call

        aggregate_failures do
          expect(result).to be_success
          expect(result.integration_error_details.owner_id).to eq(owner.id)
          expect(result.integration_error_details.owner_type).to eq(owner.class.to_s)
          expect(result.integration_error_details.error_producer_id).to eq(error_producer.id)
          expect(result.integration_error_details.error_producer.class.to_s).to eq(error_producer.class.to_s)
          expect(result.integration_error_details.details).to eq(params[:details])
        end
      end
    end
  end
end
