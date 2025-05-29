# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::DeselectInvoiceCustomSectionService, type: :service do
  describe "#call" do
    subject(:result) { described_class.call(section:, billing_entity:) }

    let(:organization) { create(:organization) }
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:section) { create(:invoice_custom_section, organization:) }

    context "when section is not selected for the billing entity" do
      it "returns a success result" do
        expect(result).to be_success
        expect(billing_entity.applied_invoice_custom_sections).to be_empty
      end
    end

    context "when section is selected for the billing entity" do
      before do
        create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: section)
      end

      it "deselects the section for the billing entity" do
        expect { result }.to change(billing_entity.selected_invoice_custom_sections, :count).by(-1)
        expect(result.section).to eq(section)
        expect(result.billing_entity).to eq(billing_entity)
        expect(billing_entity.applied_invoice_custom_sections).to be_empty
      end
    end
  end
end
