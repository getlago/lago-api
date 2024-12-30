# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invoices::Finalize, type: :graphql do
  let(:required_permission) { 'invoices:update' }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, :draft, customer:, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: FinalizeInvoiceInput!) {
        finalizeInvoice(input: $input) {
          id
          status
          taxStatus
        }
      }
    GQL
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'invoices:update'

  it 'finalizes the given invoice' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: invoice.id}
      }
    )

    result_data = result['data']['finalizeInvoice']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['status']).to eq('finalized')
    end
  end

  context 'with tax provider' do
    let(:integration) { create(:anrok_integration, organization:) }
    let(:integration_customer) { create(:anrok_customer, integration:, customer:) }

    before do
      integration_customer
    end

    it 'returns pending invoice' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: invoice.id}
        }
      )

      result_data = result['data']['finalizeInvoice']

      expect(result_data['id']).to be_present
      expect(result_data['status']).to eq('pending')
      expect(result_data['taxStatus']).to eq('pending')
    end
  end
end
