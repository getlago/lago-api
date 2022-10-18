# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNoteItem, type: :model do
  describe '#total_amount_cents' do
    let(:item) { create(:credit_note_item) }

    it { expect(item.total_amount_cents).to eq(item.credit_amount_cents) }
  end
end
