# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::FeeSerializer do
  subject(:serializer) { described_class.new(fee, root_name: 'fee') }

  let(:fee) { create(:fee) }

  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes the fee' do
    aggregate_failures do
      expect(result['fee']['lago_id']).to eq(fee.id)
      expect(result['fee']['lago_group_id']).to eq(fee.group_id)
      expect(result['fee']['amount_cents']).to eq(fee.amount_cents)
      expect(result['fee']['amount_currency']).to eq(fee.amount_currency)
      expect(result['fee']['vat_amount_cents']).to eq(fee.vat_amount_cents)
      expect(result['fee']['vat_amount_currency']).to eq(fee.vat_amount_currency)
      expect(result['fee']['total_amount_cents']).to eq(fee.total_amount_cents)
      expect(result['fee']['total_amount_currency']).to eq(fee.amount_currency)
      expect(result['fee']['units']).to eq(fee.units.to_s)
      expect(result['fee']['events_count']).to eq(fee.events_count)

      expect(result['fee']['item']['type']).to eq(fee.fee_type)
      expect(result['fee']['item']['code']).to eq(fee.item_code)
      expect(result['fee']['item']['name']).to eq(fee.item_name)
    end
  end
end
