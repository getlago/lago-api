# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ApplyInvoiceCustomSectionsService, type: :service do
  subject(:invoice_service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:) }
  let(:custom_sections) { create_list(:invoice_custom_section, 3, organization:) }

  before do
    organization.selected_invoice_custom_sections << custom_sections[1..2]
  end

  describe "#call" do
    context "when the customer has skip_invoice_custom_sections flag" do
      let(:customer) { create(:customer, organization:, skip_invoice_custom_sections: true) }

      it "does not apply any custom sections" do
        result = invoice_service.call
        expect(result).to be_success
        expect(result.applied_sections).to be_empty
        expect(invoice.reload.applied_invoice_custom_sections).to be_empty
      end
    end

    context "when the customer has custom sections" do
      before do
        customer.selected_invoice_custom_sections << custom_sections[0..1]
      end

      it "applies the custom sections to the invoice" do
        result = invoice_service.call
        expect(result).to be_success
        sections = invoice.reload.applied_invoice_custom_sections
        expect(sections.map(&:code)).to match_array(custom_sections[0..1].map(&:code))
        expect(sections.map(&:details)).to match_array(custom_sections[0..1].map(&:details))
        expect(sections.map(&:display_name)).to match_array(custom_sections[0..1].map(&:display_name))
        expect(sections.map(&:name)).to match_array(custom_sections[0..1].map(&:name))
      end
    end

    context "when the customer inherits custom sections from the organization" do
      it "applies the organization's sections to the invoice" do
        result = invoice_service.call
        expect(result).to be_success
        sections = invoice.reload.applied_invoice_custom_sections
        expect(sections.map(&:code)).to match_array(custom_sections[1..2].map(&:code))
        expect(sections.map(&:details)).to match_array(custom_sections[1..2].map(&:details))
        expect(sections.map(&:display_name)).to match_array(custom_sections[1..2].map(&:display_name))
        expect(sections.map(&:name)).to match_array(custom_sections[1..2].map(&:name))
      end
    end
  end
end
