# frozen_string_literal: true

RSpec.shared_examples "applies invoice_custom_sections" do
  let(:invoice_custom_sections) { create_list(:invoice_custom_section, 4, organization:) }

  before do
    invoice_custom_sections[2..3].each do |section|
      create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: section)
    end
  end

  context "when the customer has :skip_invoice_custom_sections flag" do
    before { customer.update!(skip_invoice_custom_sections: true) }

    it "doesn't create applied_invoice_custom_section" do
      expect { service_call }.not_to change(AppliedInvoiceCustomSection, :count)
    end
  end

  context "when customer follows billing_entity invoice_custom_sections" do
    it "creates applied_invoice_custom_sections" do
      result = service_call
      invoice = result.invoice
      expect(invoice.applied_invoice_custom_sections.pluck(:code)).to match_array(billing_entity.selected_invoice_custom_sections.pluck(:code))
    end
  end
end
