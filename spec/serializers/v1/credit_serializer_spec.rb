# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::CreditSerializer do
  subject(:serializer) { described_class.new(credit, root_name: 'credit') }

  let(:credit) { create(:credit) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['credit']['lago_id']).to eq(credit.id)
      expect(result['credit']['amount_cents']).to eq(credit.amount_cents)
      expect(result['credit']['amount_currency']).to eq(credit.amount_currency)
      expect(result['credit']['before_taxes']).to eq(false)
      expect(result['credit']['item']['lago_item_id']).to eq(credit.item_id)
      expect(result['credit']['item']['type']).to eq(credit.item_type)
      expect(result['credit']['item']['code']).to eq(credit.item_code)
      expect(result['credit']['item']['name']).to eq(credit.item_name)
      expect(result['credit']['invoice']['payment_status']).to eq(credit.invoice.payment_status)
      expect(result['credit']['invoice']['lago_id']).to eq(credit.invoice.id)
    end
  end
end
