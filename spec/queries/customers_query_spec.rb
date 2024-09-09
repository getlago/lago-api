# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomersQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, search_term:, pagination:, filters:)
  end

  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer_first) do
    create(:customer, organization:, name: 'defgh', firstname: 'John', lastname: 'Doe', external_id: '11', email: '1@example.com')
  end
  let(:customer_second) do
    create(:customer, organization:, name: 'abcde', firstname: 'Jane', lastname: 'Smith', external_id: '22', email: '2@example.com')
  end
  let(:customer_third) do
    create(:customer, organization:, name: 'presuv', firstname: 'Mary', lastname: 'Johnson', external_id: '33', email: '3@example.com')
  end

  before do
    customer_first
    customer_second
    customer_third
  end

  it 'returns all customers' do
    returned_ids = result.customers.pluck(:id)

    aggregate_failures do
      expect(result).to be_success
      expect(returned_ids.count).to eq(3)
      expect(returned_ids).to include(customer_first.id)
      expect(returned_ids).to include(customer_second.id)
      expect(returned_ids).to include(customer_third.id)
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 2} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.customers.count).to eq(1)
        expect(result.customers.current_page).to eq(2)
        expect(result.customers.prev_page).to eq(1)
        expect(result.customers.next_page).to be_nil
        expect(result.customers.total_pages).to eq(2)
        expect(result.customers.total_count).to eq(3)
      end
    end
  end

  context 'when searching for /de/ term' do
    let(:search_term) { 'de' }

    it 'returns only two customers' do
      returned_ids = result.customers.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to include(customer_first.id)
        expect(returned_ids).to include(customer_second.id)
        expect(returned_ids).not_to include(customer_third.id)
      end
    end
  end

  context 'when searching for firstname "Jane"' do
    let(:search_term) { 'Jane' }

    it 'returns only one customer' do
      returned_ids = result.customers.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).to include(customer_second.id)
        expect(returned_ids).not_to include(customer_first.id)
        expect(returned_ids).not_to include(customer_third.id)
      end
    end
  end

  context 'when searching for lastname "Johnson"' do
    let(:search_term) { 'Johnson' }

    it 'returns only one customer' do
      returned_ids = result.customers.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(customer_first.id)
        expect(returned_ids).not_to include(customer_second.id)
        expect(returned_ids).to include(customer_third.id)
      end
    end
  end
end
