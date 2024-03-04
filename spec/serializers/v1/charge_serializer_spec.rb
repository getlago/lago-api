# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::ChargeSerializer do
  subject(:serializer) { described_class.new(charge, root_name: 'charge', includes: %i[taxes]) }

  let(:charge) { create(:standard_charge) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['charge']['lago_id']).to eq(charge.id)
      expect(result['charge']['lago_billable_metric_id']).to eq(charge.billable_metric_id)
      expect(result['charge']['invoice_display_name']).to eq(charge.invoice_display_name)
      expect(result['charge']['billable_metric_code']).to eq(charge.billable_metric.code)
      expect(result['charge']['created_at']).to eq(charge.created_at.iso8601)
      expect(result['charge']['charge_model']).to eq(charge.charge_model)
      expect(result['charge']['pay_in_advance']).to eq(charge.pay_in_advance)
      expect(result['charge']['properties']).to eq(charge.properties)
      expect(result['charge']['filters']).to eq([])

      expect(result['charge']['taxes']).to eq([])
    end
  end
end
