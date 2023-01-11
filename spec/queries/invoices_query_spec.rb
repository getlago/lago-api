# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoicesQuery, type: :query do
  subject(:invoice_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer_first) { create(:customer, organization:, name: 'Rick Sanchez', email: 'pickle@hotmail.com') }
  let(:customer_second) { create(:customer, organization:, name: 'Morty Smith', email: 'ilovejessica@gmail.com') }
  let(:invoice_first) do
    create(
      :invoice,
      status: 'finalized',
      payment_status: 'succeeded',
      customer: customer_first,
    )
  end
  let(:invoice_second) do
    create(
      :invoice,
      status: 'finalized',
      payment_status: 'pending',
      customer: customer_second,
    )
  end
  let(:invoice_third) do
    create(
      :invoice,
      status: 'finalized',
      payment_status: 'failed',
      customer: customer_first,
    )
  end
  let(:invoice_fourth) do
    create(
      :invoice,
      status: 'draft',
      payment_status: 'pending',
      customer: customer_second,
    )
  end
  let(:invoice_fifth) do
    create(
      :invoice,
      status: 'draft',
      payment_status: 'pending',
      customer: customer_first,
    )
  end

  before do
    invoice_first
    invoice_second
    invoice_third
    invoice_fourth
    invoice_fifth
  end

  it 'returns all invoices' do
    result = invoice_query.call(
      search_term: nil,
      status: nil,
      payment_status: nil,
      page: 1,
      limit: 10,
    )

    returned_ids = result.invoices.pluck(:id)

    aggregate_failures do
      expect(result.invoices.count).to eq(5)
      expect(returned_ids).to include(invoice_first.id)
      expect(returned_ids).to include(invoice_second.id)
      expect(returned_ids).to include(invoice_third.id)
      expect(returned_ids).to include(invoice_fourth.id)
      expect(returned_ids).to include(invoice_fifth.id)
    end
  end

  context 'when filtering by id' do
    it 'returns only invoices specified' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        payment_status: nil,
        page: 1,
        limit: 10,
        filters: {
          ids: [invoice_second.id, invoice_fifth.id],
        },
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
      end
    end
  end

  context 'when filtering by draft status' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: 'draft',
        payment_status: nil,
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
      end
    end
  end

  context 'when filtering by failed payment_status' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        payment_status: 'failed',
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching for a part of an invoice id' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        search_term: invoice_fourth.id.scan(/.{10}/).first,
        status: nil,
        payment_status: nil,
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
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching an invoice number' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        search_term: invoice_first.number,
        status: nil,
        payment_status: nil,
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
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching a customer external id' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        search_term: customer_second.external_id,
        status: nil,
        payment_status: nil,
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching for /rick/ term' do
    it 'returns 3 invoices' do
      result = invoice_query.call(
        search_term: 'rick',
        status: nil,
        payment_status: nil,
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(3)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
      end
    end
  end

  context 'when searching for /gmail/ term' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        search_term: 'gmail',
        status: nil,
        payment_status: nil,
        page: 1,
        limit: 10,
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(2)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end
end
