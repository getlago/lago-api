# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::InvoicesResolver, type: :graphql do
  let(:required_permission) { 'invoices:view' }
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

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'invoices:view'

  it 'returns all invoices' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
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
        permissions: required_permission,
        query:
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
        permissions: required_permission,
        query:
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
        organization:
      )
    end

    let(:invoice_fourth) do
      create(
        :invoice,
        :dispute_lost,
        customer: customer_second,
        status: :finalized,
        organization:
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
        permissions: required_permission,
        query:
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

  context 'when filtering by invoice type' do
    let(:invoice_third) do
      create(
        :invoice,
        customer: customer_second,
        invoice_type: 'one_off',
        organization:
      )
    end

    let(:query) do
      <<~GQL
        query {
          invoices(limit: 5, invoiceType: one_off) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      invoice_third
    end

    it 'returns all invoices with type one_off' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
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

  context 'when filtering by currency' do
    let(:invoice_third) do
      create(
        :invoice,
        customer: customer_second,
        organization:,
        currency: 'USD'
      )
    end

    let(:query) do
      <<~GQL
        query {
          invoices(limit: 5, currency: USD) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      invoice_third
    end

    it 'returns all invoices with currency USD' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
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

  context 'when filtering by customer external id' do
    let(:invoice_third) do
      create(
        :invoice,
        customer: customer_third,
        organization:
      )
    end

    let(:customer_third) { create(:customer, organization:, external_id: "external_id") }

    let(:query) do
      <<~GQL
        query {
          invoices(limit: 5, customerExternalId: "external_id") {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      invoice_third
    end

    it 'returns all invoices with customer external id "external_id"' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
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

  context 'when filtering by issuing date' do
    let(:invoice_third) do
      create(
        :invoice,
        customer: customer_second,
        organization:,
        issuing_date: 1.week.ago
      )
    end

    let(:query) do
      <<~GQL
        query {
          invoices(
            limit: 5,
            issuingDateFrom: "#{2.weeks.ago.to_date.iso8601}",
            issuingDateTo: "#{1.week.ago.to_date.iso8601}"
          ) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      invoice_third
    end

    it 'returns all invoices issued within the from and to dates' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
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
end
