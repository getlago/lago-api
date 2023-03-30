# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::FeeSerializer do
  subject(:serializer) { described_class.new(fee, root_name: 'fee') }

  let(:subscription) { create(:subscription) }
  let(:invoice) { create(:invoice) }
  let(:fee) { create(:fee, invoice:, subscription:) }

  let(:result) { JSON.parse(serializer.to_json) }

  before do
    create(
      :invoice_subscription,
      invoice:,
      subscription:,
      properties: {
        from_datetime: Time.current,
        to_datetime: Time.current,
      },
    )
  end

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
        'payment_status' => fee.payment_status,
        'created_at' => fee.created_at&.iso8601,
        'succeeded_at' => fee.succeeded_at&.iso8601,
        'failed_at' => fee.failed_at&.iso8601,
        'refunded_at' => fee.refunded_at&.iso8601,
      )
      expect(result['fee']['item']).to include(
        'type' => fee.fee_type,
        'code' => fee.item_code,
        'name' => fee.item_name,
        'lago_item_id' => fee.item_id,
        'item_type' => fee.item_type,
      )

      expect(result['fee']['date_from']).not_to be_nil
      expect(result['fee']['date_to']).not_to be_nil
    end
  end

  context 'when fee is charge' do
    let(:charge) { create(:standard_charge) }
    let(:fee) { create(:fee, fee_type: 'charge', invoice:, subscription:, charge:) }

    it 'serializes the fees with dates boundaries' do
      expect(result['fee']['date_from']).not_to be_nil
      expect(result['fee']['date_to']).not_to be_nil
    end
  end

  context 'when fee is add_on' do
    let(:add_on) { create(:add_on) }
    let(:fee) { create(:fee, fee_type: 'add_on', invoice:, add_on:) }

    it 'does not serializes the fees with date boundaries' do
      expect(result['fee']['date_from']).to be_nil
      expect(result['fee']['date_to']).to be_nil
    end
  end
end
