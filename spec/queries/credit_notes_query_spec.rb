# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotesQuery, type: :query do
  subject(:credit_notes_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:credit_note_first) { create(:credit_note, organization:, customer:, number: '11imthefirstone') }
  let(:credit_note_second) { create(:credit_note, organization:, customer:, number: '22imthesecondone') }
  let(:credit_note_third) { create(:credit_note, organization:, customer:, number: '33imthethirdone') }
  let(:credit_note_fourth) { create(:credit_note, organization:, number: '44imthefourthone') }

  before do
    credit_note_first
    credit_note_second
    credit_note_third
    credit_note_fourth
  end

  it 'returns all credit_notes when no customer is provided' do
    result = credit_notes_query.call(
      search_term: nil,
      customer_id: nil,
      page: 1,
      limit: 10,
    )

    returned_ids = result.credit_notes.pluck(:id)

    aggregate_failures do
      expect(result.credit_notes.count).to eq(4)
      expect(returned_ids).to include(credit_note_first.id)
      expect(returned_ids).to include(credit_note_second.id)
      expect(returned_ids).to include(credit_note_third.id)
      expect(returned_ids).to include(credit_note_fourth.id)
    end
  end

  it 'returns all credit_notes of the customer' do
    result = credit_notes_query.call(
      search_term: nil,
      customer_id: customer.id,
      page: 1,
      limit: 10,
    )

    returned_ids = result.credit_notes.pluck(:id)

    aggregate_failures do
      expect(result.credit_notes.count).to eq(3)
      expect(returned_ids).to include(credit_note_first.id)
      expect(returned_ids).to include(credit_note_second.id)
      expect(returned_ids).to include(credit_note_third.id)
      expect(returned_ids).not_to include(credit_note_fourth.id)
    end
  end

  context 'when searching for /imthe/ term' do
    it 'returns three credit_notes' do
      result = credit_notes_query.call(
        search_term: 'imthe',
        customer_id: customer.id,
        page: 1,
        limit: 10,
      )

      returned_ids = result.credit_notes.pluck(:id)

      aggregate_failures do
        expect(result.credit_notes.count).to eq(3)
        expect(returned_ids).to include(credit_note_first.id)
        expect(returned_ids).to include(credit_note_second.id)
        expect(returned_ids).to include(credit_note_third.id)
        expect(returned_ids).not_to include(credit_note_fourth.id)
      end
    end
  end

  context 'when searching for /done/ term' do
    it 'returns two credit_notes' do
      result = credit_notes_query.call(
        search_term: 'done',
        customer_id: customer.id,
        page: 1,
        limit: 10,
      )

      returned_ids = result.credit_notes.pluck(:id)

      aggregate_failures do
        expect(result.credit_notes.count).to eq(2)
        expect(returned_ids).not_to include(credit_note_first.id)
        expect(returned_ids).to include(credit_note_second.id)
        expect(returned_ids).to include(credit_note_third.id)
        expect(returned_ids).not_to include(credit_note_fourth.id)
      end
    end
  end

  context 'when searching for an id' do
    it 'returns only one credit_notes' do
      result = credit_notes_query.call(
        search_term: credit_note_second.id.scan(/.{10}/).first,
        customer_id: customer.id,
        page: 1,
        limit: 10,
      )

      returned_ids = result.credit_notes.pluck(:id)

      aggregate_failures do
        expect(result.credit_notes.count).to eq(1)
        expect(returned_ids).not_to include(credit_note_first.id)
        expect(returned_ids).to include(credit_note_second.id)
        expect(returned_ids).not_to include(credit_note_third.id)
        expect(returned_ids).not_to include(credit_note_fourth.id)
      end
    end
  end

  context 'when filtering by id' do
    it 'returns only one credit_note' do
      result = credit_notes_query.call(
        search_term: nil,
        customer_id: customer.id,
        page: 1,
        limit: 10,
        filters: {
          ids: [credit_note_second.id]
        },
      )

      returned_ids = result.credit_notes.pluck(:id)

      aggregate_failures do
        expect(result.credit_notes.count).to eq(1)
        expect(returned_ids).not_to include(credit_note_first.id)
        expect(returned_ids).to include(credit_note_second.id)
        expect(returned_ids).not_to include(credit_note_third.id)
        expect(returned_ids).not_to include(credit_note_fourth.id)
      end
    end
  end

  context 'when searching for a random user' do
    it 'returns no credit_note' do
      result = credit_notes_query.call(
        search_term: nil,
        customer_id: create(:customer, organization:).id,
        page: 1,
        limit: 10,
      )

      aggregate_failures do
        expect(result.credit_notes.count).to eq(0)
      end
    end
  end
end
