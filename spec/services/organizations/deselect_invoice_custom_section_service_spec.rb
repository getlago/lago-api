# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organizations::DeselectInvoiceCustomSectionService, type: :service do
  describe '#call' do
    subject(:service_call) { described_class.call(section:) }

    let(:organization) { create(:organization) }
    let(:section) { create(:invoice_custom_section, organization:) }

    context 'when section is not selected for the organization' do
      it 'deselects the section for the organization' do
        result = service_call
        expect(result).to be_success
        expect(result.section.selected_for_organization?).to be false
      end
    end

    context 'when section is selected for the organization' do
      before do
        organization.selected_invoice_custom_sections << section
      end

      it 'deselects the section for the organization' do
        expect { service_call }.to change(organization.selected_invoice_custom_sections, :count).by(-1)
        expect(organization.invoice_custom_sections).to include(section)
        expect(section.selected_for_organization?).to be false
      end
    end
  end
end
