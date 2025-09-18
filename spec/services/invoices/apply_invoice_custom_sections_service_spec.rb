# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ApplyInvoiceCustomSectionsService do
  subject(:invoice_service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:invoice) { create(:invoice, customer:, billing_entity:) }
  let(:custom_section_1) { create(:invoice_custom_section, organization:) }
  let(:custom_section_2) { create(:invoice_custom_section, organization:) }
  let(:custom_section_3) { create(:invoice_custom_section, organization:) }

  before do
    create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: custom_section_1)
    create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: custom_section_2)
  end

  describe "#call" do
    context "when the customer has skip_invoice_custom_sections flag" do
      let(:customer) { create(:customer, organization:, billing_entity:, skip_invoice_custom_sections: true) }

      it "does not apply any custom sections" do
        result = invoice_service.call
        expect(result).to be_success
        expect(result.applied_sections).to be_empty
        expect(invoice.reload.applied_invoice_custom_sections).to be_empty
      end
    end

    context "when the customer belongs to a different billing entity" do
      let(:customer) { create(:customer, organization:, billing_entity: create(:billing_entity, organization:)) }

      it "does not apply any custom sections" do
        result = invoice_service.call
        expect(result).to be_success
        expect(result.applied_sections).to be_empty
        expect(invoice.reload.applied_invoice_custom_sections).to be_empty
      end
    end

    context "when the customer has custom sections" do
      before do
        create(:customer_applied_invoice_custom_section, organization:, billing_entity:, customer:, invoice_custom_section: custom_section_3)
      end

      it "applies the custom sections to the invoice" do
        result = invoice_service.call
        expect(result).to be_success
        sections = invoice.applied_invoice_custom_sections.reload
        expect(sections.map(&:code)).to contain_exactly(custom_section_3.code)
        expect(sections.map(&:details)).to contain_exactly(custom_section_3.details)
        expect(sections.map(&:display_name)).to contain_exactly(custom_section_3.display_name)
        expect(sections.map(&:name)).to contain_exactly(custom_section_3.name)
      end
    end

    context "when the customer inherits custom sections from the organization" do
      it "applies the organization's sections to the invoice" do
        result = invoice_service.call
        expect(result).to be_success
        sections = invoice.applied_invoice_custom_sections.reload
        expect(sections.map(&:code)).to contain_exactly(custom_section_1.code, custom_section_2.code)
        expect(sections.map(&:details)).to contain_exactly(custom_section_1.details, custom_section_2.details)
        expect(sections.map(&:display_name)).to contain_exactly(custom_section_1.display_name, custom_section_2.display_name)
        expect(sections.map(&:name)).to contain_exactly(custom_section_1.name, custom_section_2.name)
      end
    end
  end
end
