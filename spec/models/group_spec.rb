# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Group, type: :model do
  describe '#invoice_value' do
    subject(:group_invoice_name) { group.invoice_name }

    context 'when invoice value is blank' do
      let(:group) { build_stubbed(:group, invoice_value: [nil, ''].sample) }

      it 'returns value' do
        expect(group_invoice_name).to eq(group.value)
      end
    end

    context 'when invoice value is present' do
      let(:group) { build_stubbed(:group) }

      it 'returns invoice value' do
        expect(group_invoice_name).to eq(group.__send__(:invoice_value))
      end
    end
  end
end
