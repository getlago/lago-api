# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::AppliedTaxSerializer do
  subject(:serializer) { described_class.new(applied_tax, root_name: 'applied_tax') }

  let(:applied_tax) { create(:applied_tax) }

  before { applied_tax }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['applied_tax']['lago_id']).to eq(applied_tax.id)
      expect(result['applied_tax']['lago_customer_id']).to eq(applied_tax.customer.id)
      expect(result['applied_tax']['lago_tax_id']).to eq(applied_tax.tax.id)
      expect(result['applied_tax']['tax_code']).to eq(applied_tax.tax.code)
      expect(result['applied_tax']['external_customer_id']).to eq(applied_tax.customer.external_id)
    end
  end
end
