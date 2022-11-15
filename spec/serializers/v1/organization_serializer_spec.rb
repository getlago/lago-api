# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::OrganizationSerializer do
  subject(:serializer) { described_class.new(organization, root_name: 'organization') }

  let(:organization) { create(:organization) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['organization']['name']).to eq(organization.name)
      expect(result['organization']['created_at']).to eq(organization.created_at.iso8601)
      expect(result['organization']['webhook_url']).to eq(organization.webhook_url)
      expect(result['organization']['vat_rate']).to eq(organization.vat_rate)
      expect(result['organization']['country']).to eq(organization.country)
      expect(result['organization']['address_line1']).to eq(organization.address_line1)
      expect(result['organization']['address_line2']).to eq(organization.address_line2)
      expect(result['organization']['state']).to eq(organization.state)
      expect(result['organization']['zipcode']).to eq(organization.zipcode)
      expect(result['organization']['email']).to eq(organization.email)
      expect(result['organization']['city']).to eq(organization.city)
      expect(result['organization']['legal_name']).to eq(organization.legal_name)
      expect(result['organization']['legal_number']).to eq(organization.legal_number)
      expect(result['organization']['invoice_footer']).to eq(organization.invoice_footer)
      expect(result['organization']['invoice_grace_period']).to eq(organization.invoice_grace_period)
    end
  end
end
