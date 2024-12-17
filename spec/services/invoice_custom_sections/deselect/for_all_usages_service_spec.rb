# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceCustomSections::Deselect::ForAllUsagesService, type: :service do
  describe '#call' do
    subject(:service_result) { described_class.call(section:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer) }
    let(:section) { create(:invoice_custom_section) }

    context 'when the section is selected' do
      before do
        organization.selected_invoice_custom_sections << section
        customer.selected_invoice_custom_sections << section
      end

      it 'selects the section for the organization' do
        expect { service_result }.to change(organization.selected_invoice_custom_sections, :count).from(1).to(0)
          .and change(customer.selected_invoice_custom_sections, :count).from(1).to(0)
        expect(InvoiceCustomSectionSelection.count).to eq(0)
      end
    end

    context 'when the section is not selected' do
      it 'selects the section for the organization' do
        service_result
        expect(InvoiceCustomSectionSelection.count).to eq(0)
      end
    end
  end
end
