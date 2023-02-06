# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invoices::RetryAllPayments, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:user) { membership.user }
  let(:gocardless_payment_provider) { create(:gocardless_provider, organization:) }
  let(:customer_first) { create(:customer, organization:, payment_provider: 'gocardless') }
  let(:gocardless_customer_first) { create(:gocardless_customer, customer: customer_first) }
  let(:customer_second) { create(:customer, organization:, payment_provider: 'gocardless') }
  let(:gocardless_customer_second) { create(:gocardless_customer, customer: customer_second) }
  let(:mutation) do
    <<-GQL
      mutation($input: RetryAllInvoicePaymentsInput!) {
        retryAllInvoicePayments(input: $input) {
          collection { id }
        }
      }
    GQL
  end

  context 'with valid preconditions' do
    let(:invoice_first) do
      create(
        :invoice,
        organization:,
        customer: customer_first,
        status: 'finalized',
        payment_status: 'failed',
        ready_for_payment_processing: true,
      )
    end
    let(:invoice_second) do
      create(
        :invoice,
        organization:,
        customer: customer_second,
        status: 'finalized',
        payment_status: 'failed',
        ready_for_payment_processing: true,
      )
    end

    before do
      gocardless_payment_provider
      gocardless_customer_first
      gocardless_customer_second
      invoice_first
      invoice_second
    end

    it 'returns the invoices that are scheduled for retry' do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        query: mutation,
        variables: {
          input: {},
        },
      )

      data = result['data']['retryAllInvoicePayments']
      invoice_ids = data['collection'].map { |value| value['id'] }

      expect(invoice_ids).to include(invoice_first.id)
      expect(invoice_ids).to include(invoice_second.id)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: {},
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: user,
        query: mutation,
        variables: {
          input: {},
        },
      )

      expect_forbidden_error(result)
    end
  end
end
