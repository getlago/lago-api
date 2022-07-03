# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::ChargeSerializer do
  subject(:serializer) { described_class.new(charge, root_name: 'charge') }

  let(:charge) { create(:standard_charge) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['charge']['lago_id']).to eq(charge.id)
      expect(result['charge']['lago_billable_metric_id']).to eq(charge.billable_metric_id)
      expect(result['charge']['created_at']).to eq(charge.created_at.iso8601)
      expect(result['charge']['amount_currency']).to eq(charge.amount_currency)
      expect(result['charge']['charge_model']).to eq(charge.charge_model)
      expect(result['charge']['properties']).to eq(charge.properties)
    end
  end
end
