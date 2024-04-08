# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::InvoicesResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        invoices(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer_first) { create(:customer, organization:) }
  let(:customer_second) { create(:customer, organization:) }
  let(:invoice_first) do
    create(:invoice, customer: customer_first, payment_status: :pending, status: :finalized, organization:)
  end
  let(:invoice_second) do
    create(:invoice, customer: customer_second, payment_status: :succeeded, status: :finalized, organization:)
  end

  before do
    invoice_first
    invoice_second
  end

  it 'returns all invoices' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
    )

    invoices_response = result['data']['invoices']
    returned_ids = invoices_response['collection'].map { |hash| hash['id'] }

    aggregate_failures do
      expect(invoices_response['collection'].count).to eq(2)
      expect(returned_ids).to include(invoice_first.id)
      expect(returned_ids).to include(invoice_second.id)

      expect(invoices_response['metadata']['currentPage']).to eq(1)
      expect(invoices_response['metadata']['totalCount']).to eq(2)
    end
  end

  context 'when filtering by succeeded payment status' do
    let(:query) do
      <<~GQL
        query {
          invoices(limit: 5, paymentStatus: [succeeded]) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it 'returns all succeeded invoices' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      invoices_response = result['data']['invoices']
      returned_ids = invoices_response['collection'].map { |hash| hash['id'] }

      aggregate_failures do
        expect(invoices_response['collection'].count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)

        expect(invoices_response['metadata']['currentPage']).to eq(1)
        expect(invoices_response['metadata']['totalCount']).to eq(1)
      end
    end
  end

  context 'when filtering by draft status' do
    let(:invoice_third) { create(:invoice, customer: customer_second, status: :draft, organization:) }
    let(:query) do
      <<~GQL
        query {
          invoices(limit: 5, status: draft) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before { invoice_third }

    it 'returns all draft invoices' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      invoices_response = result['data']['invoices']

      aggregate_failures do
        expect(invoices_response['collection'].count).to eq(1)
        expect(invoices_response['collection'].first['id']).to eq(invoice_third.id)

        expect(invoices_response['metadata']['currentPage']).to eq(1)
        expect(invoices_response['metadata']['totalCount']).to eq(1)
      end
    end
  end

  context 'when filtering by payment dispute lost' do
    let(:invoice_third) do
      create(
        :invoice,
        customer: customer_second,
        status: :draft,
        organization:,
      )
    end

    let(:invoice_fourth) do
      create(
        :invoice,
        :dispute_lost,
        customer: customer_second,
        status: :finalized,
        organization:,
      )
    end

    let(:query) do
      <<~GQL
        query {
          invoices(limit: 5, paymentDisputeLost: true) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      invoice_third
      invoice_fourth
    end

    it 'returns all invoices with payment dispute lost' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      invoices_response = result['data']['invoices']

      aggregate_failures do
        expect(invoices_response['collection'].count).to eq(1)
        expect(invoices_response['collection'].first['id']).to eq(invoice_fourth.id)

        expect(invoices_response['metadata']['currentPage']).to eq(1)
        expect(invoices_response['metadata']['totalCount']).to eq(1)
      end
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'Not in organization',
      )
    end
  end
end
