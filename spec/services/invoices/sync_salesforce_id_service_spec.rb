# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::SyncSalesforceIdService, type: :service do
  subject(:sync_salesforce_id_service) { described_class.new(invoice:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:integration) { create(:salesforce_integration, organization:) }
  let(:params) { {} }

  describe '#call' do
    context 'when the invoice is nil' do
      let(:invoice) { nil }

      it 'returns an error' do
        result = sync_salesforce_id_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('invoice_not_found')
      end
    end

    context 'when the integration is nil' do
      let(:invoice) { create(:invoice, organization:) }
      #let!(:integration) { create(:salesforce_integration, organization:) }

      it 'returns an error' do
        result = sync_salesforce_id_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('integration_not_found')
      end
    end

    context 'when the integration resource does not exist' do
      xit 'creates a new integration resource' do
      end
    end
  end
end
