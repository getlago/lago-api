# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organizations::UpdateService do
  subject(:organization_update_service) { described_class.new(organization) }

  let(:organization) { create(:organization) }

  describe '.update' do
    it 'updates the organization' do
      result = organization_update_service.update(
        webhook_url: 'http://foo.bar',
        vat_rate: 12.5,
      )

      expect(result.organization.webhook_url).to eq('http://foo.bar')
      expect(result.organization.vat_rate).to eq(12.5)
    end
  end
end
