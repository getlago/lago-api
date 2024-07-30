# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotesQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, search_term:, pagination:, filters:)
  end

  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:other_org_customer) { create(:customer) }
  let(:credit_note_first) { create(:credit_note, customer:, number: '11imthefirstone') }
  let(:credit_note_second) { create(:credit_note, customer:, number: '22imthesecondone') }
  let(:credit_note_third) { create(:credit_note, customer:, number: '33imthethirdone') }
  let(:credit_note_fourth) { create(:credit_note, customer: create(:customer, organization:), number: '44imthefourthone') }
  let(:other_org_credit_note) { create(:credit_note, customer: other_org_customer, number: '55imthefifthone') }

  before do
    credit_note_first
    credit_note_second
    credit_note_third
    credit_note_fourth
    other_org_credit_note
  end

  it 'returns all credit_notes' do
    returned_ids = result.credit_notes.pluck(:id)

    aggregate_failures do
      expect(result).to be_success
      expect(returned_ids.count).to eq(4)
      expect(returned_ids).to include(credit_note_first.id)
      expect(returned_ids).to include(credit_note_second.id)
      expect(returned_ids).to include(credit_note_third.id)
      expect(returned_ids).to include(credit_note_fourth.id)
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 3} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.credit_notes.count).to eq(1)
        expect(result.credit_notes.current_page).to eq(2)
        expect(result.credit_notes.prev_page).to eq(1)
        expect(result.credit_notes.next_page).to be_nil
        expect(result.credit_notes.total_pages).to eq(2)
        expect(result.credit_notes.total_count).to eq(4)
      end
    end
  end

  context 'when filtering by customer_id' do
    let(:filters) { {customer_id: customer.id} }

    it 'returns all credit_notes of the customer' do
      returned_ids = result.credit_notes.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(3)
        expect(returned_ids).to include(credit_note_first.id)
        expect(returned_ids).to include(credit_note_second.id)
        expect(returned_ids).to include(credit_note_third.id)
        expect(returned_ids).not_to include(credit_note_fourth.id)
      end
    end
  end

  context 'when filtering by a customer_id from other organization' do
    let(:filters) { {customer_id: other_org_credit_note.customer.id} }

    it 'returns an empty result' do
      expect(result.credit_notes).to be_empty
    end
  end

  context 'when searching for /imthe/ term and filtering by customer_id' do
    let(:search_term) { 'imthe' }
    let(:filters) { {customer_id: customer.id} }

    it 'returns matching credit_notes' do
      returned_ids = result.credit_notes.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(3)
        expect(returned_ids).to include(credit_note_first.id)
        expect(returned_ids).to include(credit_note_second.id)
        expect(returned_ids).to include(credit_note_third.id)
        expect(returned_ids).not_to include(credit_note_fourth.id)
      end
    end
  end

  context 'when searching for /done/ term' do
    let(:search_term) { 'done' }

    it 'returns matching credit_notes' do
      returned_ids = result.credit_notes.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).not_to include(credit_note_first.id)
        expect(returned_ids).to include(credit_note_second.id)
        expect(returned_ids).to include(credit_note_third.id)
        expect(returned_ids).not_to include(credit_note_fourth.id)
      end
    end
  end

  context 'when searching for an id' do
    let(:search_term) { credit_note_second.id.scan(/.{10}/).first }

    it 'returns matching credit_notes' do
      returned_ids = result.credit_notes.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(credit_note_first.id)
        expect(returned_ids).to include(credit_note_second.id)
        expect(returned_ids).not_to include(credit_note_third.id)
        expect(returned_ids).not_to include(credit_note_fourth.id)
      end
    end
  end
end
