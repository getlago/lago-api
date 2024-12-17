# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceCustomSections::Deselect::ForOrganizationService, type: :service do
  describe '#call' do
    subject(:service_result) { described_class.call(section:) }

    let(:organization) { create(:organization) }
    let(:section) { create(:invoice_custom_section, organization:) }

    context 'when the section is selected' do
      before { organization.selected_invoice_custom_sections << section }

      it 'selects the section for the organization' do
        expect { service_result }.to change(organization.reload.selected_invoice_custom_sections, :count).from(1).to(0)
        expect(service_result).to be_success
        expect(organization.selected_invoice_custom_sections).to eq([])
      end
    end

    context 'when the section is not selected' do
      it 'does not fail' do
        service_result
        expect(organization.selected_invoice_custom_sections).to eq([])
      end
    end
  end
end
