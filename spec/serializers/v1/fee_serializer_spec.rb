# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::FeeSerializer do
  subject(:serializer) { described_class.new(fee, root_name: 'fee') }

  let(:fee) { create(:fee) }

  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes the fee' do
    aggregate_failures do
      expect(result['fee']).to include(
        'lago_id' => fee.id,
        'lago_group_id' => fee.group_id,
        'amount_cents' => fee.amount_cents,
        'amount_currency' => fee.amount_currency,
        'vat_amount_cents' => fee.vat_amount_cents,
        'vat_amount_currency' => fee.vat_amount_currency,
        'total_amount_cents' => fee.total_amount_cents,
        'total_amount_currency' => fee.amount_currency,
        'units' => fee.units.to_s,
        'events_count' => fee.events_count,
      )
      expect(result['fee']['item']).to include(
        'type' => fee.fee_type,
        'code' => fee.item_code,
        'name' => fee.item_name,
        'lago_item_id' => fee.item_id,
        'item_type' => fee.item_type,
      )
    end
  end
end
