# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::TaxRateSerializer do
  subject(:serializer) { described_class.new(tax_rate, root_name: 'tax_rate') }

  let(:tax_rate) { create(:tax_rate) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['tax_rate']['lago_id']).to eq(tax_rate.id)
      expect(result['tax_rate']['name']).to eq(tax_rate.name)
      expect(result['tax_rate']['code']).to eq(tax_rate.code)
      expect(result['tax_rate']['value']).to eq(tax_rate.value)
      expect(result['tax_rate']['description']).to eq(tax_rate.description)
      expect(result['tax_rate']['created_at']).to eq(tax_rate.created_at.iso8601)
    end
  end
end
