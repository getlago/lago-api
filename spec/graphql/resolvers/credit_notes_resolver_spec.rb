# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CreditNotesResolver, type: :graphql do
  let(:required_permission) { 'credit_notes:view' }
  let(:query) do
    <<~GQL
      query {
        creditNotes(customerId: "#{customer_id}", searchTerm: "#{search_term}", limit: 5) {
          collection { id number }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:credit_note) { create(:credit_note, organization:, customer:) }
  let(:customer_id) { nil }
  let(:search_term) { nil }

  before do
    subscription
    credit_note
    create(:credit_note, :draft, organization:, customer:)
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'credit_notes:view'

  it 'returns a list of finalized credit_notes' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    credit_notes_response = result['data']['creditNotes']

    aggregate_failures do
      expect(credit_notes_response['collection'].count).to eq(1)
      expect(credit_notes_response['collection'].first['id']).to eq(credit_note.id)

      expect(credit_notes_response['metadata']['currentPage']).to eq(1)
      expect(credit_notes_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'with customer_id' do
    let(:customer_id) { customer.id }

    it 'returns a list of finalized credit_notes for a customer' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      credit_notes_response = result['data']['creditNotes']

      aggregate_failures do
        expect(credit_notes_response['collection'].count).to eq(1)
        expect(credit_notes_response['collection'].first['id']).to eq(credit_note.id)

        expect(credit_notes_response['metadata']['currentPage']).to eq(1)
        expect(credit_notes_response['metadata']['totalCount']).to eq(1)
      end
    end
  end

  context 'with search_terms' do
    let(:search_term) { "yolo" }

    it 'returns a list of finalized credit_notes matching the terms' do
      create(:credit_note, number: 'yolo', organization:)

      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      credit_notes_response = result['data']['creditNotes']

      aggregate_failures do
        expect(credit_notes_response['collection'].count).to eq(1)
        expect(credit_notes_response['collection'].first['number']).to eq("yolo")

        expect(credit_notes_response['metadata']['currentPage']).to eq(1)
        expect(credit_notes_response['metadata']['totalCount']).to eq(1)
      end
    end
  end

  context 'when customer does not exists' do
    let(:customer_id) { 'unknown' }

    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      credit_notes_response = result['data']['creditNotes']

      expect(credit_notes_response['collection']).to be_empty
    end
  end
end
