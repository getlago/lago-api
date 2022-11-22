# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::OrganizationSerializer do
  subject(:serializer) { described_class.new(org, root_name: 'organization') }

  let(:org) { create(:organization) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['organization']['name']).to eq(org.name)
      expect(result['organization']['created_at']).to eq(org.created_at.iso8601)
      expect(result['organization']['webhook_url']).to eq(org.webhook_url)
      expect(result['organization']['country']).to eq(org.country)
      expect(result['organization']['address_line1']).to eq(org.address_line1)
      expect(result['organization']['address_line2']).to eq(org.address_line2)
      expect(result['organization']['state']).to eq(org.state)
      expect(result['organization']['zipcode']).to eq(org.zipcode)
      expect(result['organization']['email']).to eq(org.email)
      expect(result['organization']['city']).to eq(org.city)
      expect(result['organization']['legal_name']).to eq(org.legal_name)
      expect(result['organization']['legal_number']).to eq(org.legal_number)
      expect(result['organization']['billing_configuration']['invoice_footer']).to eq(org.invoice_footer)
      expect(result['organization']['billing_configuration']['invoice_grace_period']).to eq(org.invoice_grace_period)
      expect(result['organization']['billing_configuration']['vat_rate']).to eq(org.vat_rate)
      expect(result['organization']['timezone']).to eq(org.timezone)
    end
  end
end
