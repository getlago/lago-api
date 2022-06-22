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

    context 'with base64 logo' do
      let(:base64_logo) do
        logo_file = File.open(Rails.root.join('spec/factories/images/logo.png')).read
        base64_logo = Base64.encode64(logo_file)

        "data:image/png;base64,#{base64_logo}"
      end

      it 'updates the organization with logo' do
        result = organization_update_service.update(
          logo: base64_logo,
        )

        expect(result.organization.logo.blob).not_to be_nil
      end
    end
  end
end
