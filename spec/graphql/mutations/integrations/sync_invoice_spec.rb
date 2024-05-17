# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Integrations::SyncInvoice, type: :graphql do
  subject(:execute_graphql_call) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {invoiceId: invoice.id},
      },
    )
  end

  let(:required_permission) { 'organization:integrations:delete' }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:integration_customer) { create(:netsuite_customer, customer:, integration:) }
  let(:integration) { create(:netsuite_integration, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: SyncIntegrationInvoiceInput!) {
        syncIntegrationInvoice(input: $input) { invoiceId }
      }
    GQL
  end

  before { subject }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:update'

  it 'syncs an invoice' do
    # expect(::Integrations::Aggregator::Invoices::CreateJob).to have_received(:perform_later).with(invoice:)
    pending
  end
end
