# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::AppliedTaxRateSerializer do
  subject(:serializer) { described_class.new(applied_tax_rate, root_name: 'applied_tax_rate') }

  let(:applied_tax_rate) { create(:applied_tax_rate) }

  before { applied_tax_rate }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['applied_tax_rate']['lago_id']).to eq(applied_tax_rate.id)
      expect(result['applied_tax_rate']['lago_customer_id']).to eq(applied_tax_rate.customer.id)
      expect(result['applied_tax_rate']['lago_tax_rate_id']).to eq(applied_tax_rate.tax_rate.id)
      expect(result['applied_tax_rate']['tax_rate_code']).to eq(applied_tax_rate.tax_rate.code)
      expect(result['applied_tax_rate']['external_customer_id']).to eq(applied_tax_rate.customer.external_id)
    end
  end
end
