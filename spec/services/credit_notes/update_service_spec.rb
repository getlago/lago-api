# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::UpdateService, type: :service do
  subject(:credit_note_service) { described_class.new(credit_note: credit_note, **params) }

  let(:credit_note) { create(:credit_note) }

  let(:params) do
    { refund_status: 'succeeded' }
  end

  it 'updates the credit note status' do
    result = credit_note_service.call

    aggregate_failures do
      expect(result).to be_success
      expect(result.credit_note.refund_status).to eq('succeeded')
    end
  end

  context 'with invalid refund status' do
    let(:params) do
      { refund_status: 'foo_bar' }
    end

    it 'returns an error' do
      result = credit_note_service.call

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:refund_status)
        expect(result.error.messages[:refund_status]).to include('value_is_invalid')
      end
    end
  end
end
