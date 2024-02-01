# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FeeDisplayHelper do
  subject(:helper) { described_class }

  describe '.grouped_by_display' do
    let(:charge) { create(:standard_charge, properties:) }
    let(:fee) { create(:fee, charge:, fee_type: 'charge', grouped_by:, total_aggregated_units: 10) }
    let(:grouped_by) do
      {
        'key_1' => 'mercredi',
        'key_2' => 'week_01',
        'key_3' => '2024',
      }
    end
    let(:properties) do
      {
        'amount' => '5',
        'grouped_by' => %w[key_1 key_2 key_3],
      }
    end

    context 'when it is standard charge fee with grouped_by property' do
      it 'returns valid response' do
        expect(helper.grouped_by_display(fee)).to eq(' • mercredi • week_01 • 2024')
      end
    end

    context 'when missing grouped_by property' do
      let(:properties) do
        {
          'amount' => '5',
        }
      end

      it 'returns valid response' do
        expect(helper.grouped_by_display(fee)).to eq('')
      end
    end

    context 'when some values are nil' do
      let(:properties) do
        {
          'amount' => '5',
          'grouped_by' => ['key_2', 'key_3', nil],
        }
      end

      it 'returns valid response' do
        expect(helper.grouped_by_display(fee)).to eq(' • week_01 • 2024')
      end
    end
  end
end
