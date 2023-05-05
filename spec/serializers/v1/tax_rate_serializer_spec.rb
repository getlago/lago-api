# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::TaxRateSerializer do
  subject(:serializer) { described_class.new(tax_rate, root_name: 'tax_rate') }

  let(:tax_rate) { create(:tax_rate) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    expect(result['tax_rate']).to include(
      'lago_id' => tax_rate.id,
      'name' => tax_rate.name,
      'code' => tax_rate.code,
      'value' => tax_rate.value,
      'description' => tax_rate.description,
      'customers_count' => 0,
      'created_at' => tax_rate.created_at.iso8601,
    )
  end
end
