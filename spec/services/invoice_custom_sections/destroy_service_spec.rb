# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceCustomSections::DestroyService do
  subject(:service_result) { described_class.call(invoice_custom_section:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer) }
  let(:invoice_custom_section) { create(:invoice_custom_section, organization:) }

  before do
    allow(InvoiceCustomSections::DeselectAllService).to receive(:call).and_call_original
    organization.selected_invoice_custom_sections << invoice_custom_section
    customer.selected_invoice_custom_sections << invoice_custom_section
  end

  describe '#call' do
    context 'when destroy is successful' do
      it 'discards the invoice custom section and destroys all selections' do
        result = service_result

        expect(result.invoice_custom_section.discarded?).to be(true)
        expect(InvoiceCustomSections::DeselectAllService).to have_received(:call)
          .with(section: invoice_custom_section)
        expect(organization.selected_invoice_custom_sections).to eq([])
        expect(customer.selected_invoice_custom_sections).to eq([])
        expect(customer.applicable_invoice_custom_sections).to eq([])
      end
    end
  end
end
