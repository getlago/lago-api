# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoicesQuery, type: :query do
  subject(:invoice_query) do
    described_class.new(organization:, pagination:)
  end

  let(:pagination) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer_first) { create(:customer, organization:, name: 'Rick Sanchez', email: 'pickle@hotmail.com') }
  let(:customer_second) { create(:customer, organization:, name: 'Morty Smith', email: 'ilovejessica@gmail.com') }
  let(:invoice_first) do
    create(
      :invoice,
      organization:,
      status: 'finalized',
      payment_status: 'succeeded',
      customer: customer_first,
      number: '1111111111',
      issuing_date: 1.week.ago
    )
  end
  let(:invoice_second) do
    create(
      :invoice,
      organization:,
      status: 'finalized',
      payment_status: 'pending',
      customer: customer_second,
      number: '2222222222',
      issuing_date: 2.weeks.ago
    )
  end
  let(:invoice_third) do
    create(
      :invoice,
      organization:,
      status: 'finalized',
      payment_status: 'failed',
      payment_overdue: true,
      customer: customer_first,
      number: '3333333333',
      issuing_date: 3.weeks.ago
    )
  end
  let(:invoice_fourth) do
    create(
      :invoice,
      organization:,
      status: 'draft',
      payment_status: 'pending',
      customer: customer_second,
      number: '4444444444',
      currency: 'USD'
    )
  end
  let(:invoice_fifth) do
    create(
      :invoice,
      :credit,
      organization:,
      status: 'draft',
      payment_status: 'pending',
      customer: customer_first,
      number: '5555555555'
    )
  end
  let(:invoice_sixth) do
    create(
      :invoice,
      :dispute_lost,
      organization:,
      payment_status: 'pending',
      customer: customer_first,
      number: '6666666666'
    )
  end

  before do
    invoice_first
    invoice_second
    invoice_third
    invoice_fourth
    invoice_fifth
    invoice_sixth
  end

  it 'returns all invoices' do
    result = invoice_query.call(
      search_term: nil,
      status: nil,
      payment_status: nil
    )

    returned_ids = result.invoices.pluck(:id)

    aggregate_failures do
      expect(result.invoices.count).to eq(6)
      expect(returned_ids).to include(invoice_first.id)
      expect(returned_ids).to include(invoice_second.id)
      expect(returned_ids).to include(invoice_third.id)
      expect(returned_ids).to include(invoice_fourth.id)
      expect(returned_ids).to include(invoice_fifth.id)
      expect(returned_ids).to include(invoice_sixth.id)
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 3} }

    it 'applies the pagination' do
      result = invoice_query.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.invoices.count).to eq(3)
        expect(result.invoices.current_page).to eq(2)
        expect(result.invoices.prev_page).to eq(1)
        expect(result.invoices.next_page).to be_nil
        expect(result.invoices.total_pages).to eq(2)
        expect(result.invoices.total_count).to eq(6)
      end
    end
  end

  context 'when filtering by draft status' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: 'draft',
        payment_status: nil
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
        payment_status: 'failed'
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

  context 'when filtering by succeeded and failed payment_status' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        payment_status: ['succeeded', 'failed']
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(2)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
      end
    end
  end

  context 'when filtering by payment dispute lost' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        payment_dispute_lost: true
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).not_to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).not_to include(invoice_fifth.id)
        expect(returned_ids).to include(invoice_sixth.id)
      end
    end
  end

  context 'when filtering by payment dispute lost false' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        payment_dispute_lost: false
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(5)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
        expect(returned_ids).not_to include(invoice_sixth.id)
      end
    end
  end

  context 'when filtering by payment overdue' do
    it 'returns expected invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        payment_overdue: true
      )

      expect(result.invoices.pluck(:id)).to eq([invoice_third.id])
    end
  end

  context 'when filtering by credit invoice_type' do
    it 'returns 1 invoice' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        filters: {
          invoice_type: 'credit'
        }
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(returned_ids).to eq [invoice_fifth.id]
      end
    end
  end

  context 'when filtering by USD currency' do
    it 'returns 1 invoice' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        filters: {
          currency: 'USD'
        }
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(returned_ids).to eq [invoice_fourth.id]
      end
    end
  end

  context 'when filtering by customer_external_id' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        filters: {
          customer_external_id: customer_second.external_id
        }
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(returned_ids).to contain_exactly(
          invoice_second.id,
          invoice_fourth.id
        )
      end
    end
  end

  context 'when filtering by issuing_date_from' do
    it 'returns 4 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        filters: {
          issuing_date_from: 2.days.ago.iso8601.to_date.to_s
        }
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(returned_ids).to contain_exactly(
          invoice_fourth.id,
          invoice_fifth.id,
          invoice_sixth.id
        )
      end
    end

    context 'with invalid date' do
      it 'returns a failed result' do
        result = invoice_query.call(
          search_term: nil,
          status: nil,
          filters: {
            issuing_date_from: 'invalid_date_value'
          }
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:issuing_date_from]).to include('invalid_date')
        end
      end
    end
  end

  context 'when filtering by issuing_date_to' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        filters: {
          issuing_date_to: 2.weeks.ago.iso8601.to_date.to_s
        }
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(returned_ids).to contain_exactly(
          invoice_second.id,
          invoice_third.id
        )
      end
    end

    context 'with invalid date' do
      it 'returns a failed result' do
        result = invoice_query.call(
          search_term: nil,
          status: nil,
          filters: {
            issuing_date_to: 'invalid_date_value'
          }
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:issuing_date_to]).to include('invalid_date')
        end
      end
    end
  end

  context 'when filtering by issuing_date from and to' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        search_term: nil,
        status: nil,
        filters: {
          issuing_date_from: 2.weeks.ago.iso8601,
          issuing_date_to: 1.week.ago.iso8601
        }
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(returned_ids).to contain_exactly(
          invoice_first.id,
          invoice_second.id
        )
      end
    end
  end

  context 'when searching for a part of an invoice id' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        search_term: invoice_fourth.id.scan(/.{10}/).first,
        status: nil,
        payment_status: nil
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
        payment_status: nil
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
        payment_status: nil
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
        payment_status: nil
      )

      returned_ids = result.invoices.pluck(:id)

      aggregate_failures do
        expect(result.invoices.count).to eq(4)
        expect(returned_ids).to include(invoice_first.id)
        expect(returned_ids).not_to include(invoice_second.id)
        expect(returned_ids).to include(invoice_third.id)
        expect(returned_ids).not_to include(invoice_fourth.id)
        expect(returned_ids).to include(invoice_fifth.id)
        expect(returned_ids).to include(invoice_sixth.id)
      end
    end
  end

  context 'when searching for /gmail/ term' do
    it 'returns 2 invoices' do
      result = invoice_query.call(
        search_term: 'gmail',
        status: nil,
        payment_status: nil
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

  context 'when searching for /44444444/ term' do
    it 'returns 1 invoices' do
      result = invoice_query.call(
        customer_id: customer_second.id,
        search_term: '44444444',
        status: nil
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

  context 'when searching for another customer with no invoice' do
    it 'returns 0 invoices' do
      result = invoice_query.call(
        customer_id: create(:customer, organization:).id,
        search_term: nil,
        status: nil
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
