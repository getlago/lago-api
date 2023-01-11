# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomerInvoicesQuery, type: :query do
  subject(:invoice_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, name: 'Spike Spiegel', email: 'spike@swordfish.com') }
  let(:invoice_first) do
    create(
      :invoice,
      customer:,
      status: 'finalized',
      number: '1111111111',
    )
  end
  let(:invoice_second) do
    create(
      :invoice,
      customer:,
      status: 'finalized',
      number: '2222222222',
    )
  end
  let(:invoice_third) do
    create(
      :invoice,
      customer:,
      status: 'draft',
      number: '3333333333',
    )
  end
  let(:invoice_fourth) do
    create(
      :invoice,
      customer:,
      status: 'draft',
      number: '4444444444',
    )
  end

  before do
    invoice_first
    invoice_second
    invoice_third
    invoice_fourth
  end

  it 'returns all customer invoices' do
    result = invoice_query.call(
      customer_id: customer.id,
      search_term: nil,
      status: nil,
      page: 1,
      limit: 10,
    )

    returned_ids = result.invoices.pluck(:id)

    aggregate_failures do
      expect(result.invoices.count).to eq(4)
      expect(returned_ids).to include(invoice_first.id)
      expect(returned_ids).to include(invoice_second.id)
      expect(returned_ids).to include(invoice_third.id)
      expect(returned_ids).to include(invoice_fourth.id)
    end
  end

  context 'when filtering by draft status' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        customer_id: customer.id,
        search_term: nil,
        status: 'draft',
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
      end
    end
  end

  context 'when searching an invoice number' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        customer_id: customer.id,
        search_term: invoice_first.number,
        status: nil,
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(1)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
      end
    end
  end

  context 'when searching for /44444444/ term' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        customer_id: customer.id,
        search_term: '44444444',
        status: nil,
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
      end
    end
  end

  context 'when searching for another customer with no invoice' do
    it 'returns 0 invoices' do
      result = invoice_query.call(
        customer_id: create(:customer, organization:).id,
        search_term: nil,
        status: nil,
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(0)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
      end
    end
  end
end
