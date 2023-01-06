# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::CustomerQuery, type: :service do
  subject(:customer_query) do
    described_class.new(organization: organization)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer_first) { create(:customer, organization: organization, name: 'defgh') }
  let(:customer_second) { create(:customer, organization: organization, name: 'abcde') }
  let(:customer_third) { create(:customer, organization: organization, name: 'presuv') }

  before do
    customer_first
    customer_second
    customer_third
  end

  it 'returns all customers' do
    result = customer_query.call(
      search_term: nil,
      page: 1,
      limit: 10,
    )

    returned_ids = result.customers.pluck(:id)

    aggregate_failures do
      expect(result.customers.count).to eq(3)
      expect(returned_ids).to include(customer_first.id)
      expect(returned_ids).to include(customer_second.id)
      expect(returned_ids).to include(customer_third.id)
    end
  end

  context 'when searching for /de/ term' do
    it 'returns only two customers' do
      result = customer_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
      )

      returned_ids = result.customers.pluck(:id)

      aggregate_failures do
        expect(result.customers.count).to eq(2)
        expect(returned_ids).to include(customer_first.id)
        expect(returned_ids).to include(customer_second.id)
        expect(returned_ids).not_to include(customer_third.id)
      end
    end
  end

  context 'when searching for /de/ term and filtering by id' do
    it 'returns only one customer' do
      result = customer_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
        filters: {
          ids: [customer_second.id],
        },
      )

      returned_ids = result.customers.pluck(:id)

      aggregate_failures do
        expect(result.customers.count).to eq(1)
        expect(returned_ids).not_to include(customer_first.id)
        expect(returned_ids).to include(customer_second.id)
        expect(returned_ids).not_to include(customer_third.id)
      end
    end
  end
end
