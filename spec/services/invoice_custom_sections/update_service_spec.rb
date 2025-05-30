# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceCustomSections::UpdateService do
  subject(:service_result) { described_class.call(invoice_custom_section:, update_params:, selected:) }

  let(:organization) { create(:organization) }
  let(:default_billing_entity) { organization.default_billing_entity }
  let(:invoice_custom_section) { create(:invoice_custom_section, organization:) }
  let(:update_params) { {name: "Updated Name"} }
  let(:selected) { true }

  before do
    allow(BillingEntities::SelectInvoiceCustomSectionService).to receive(:call!).and_call_original
    allow(BillingEntities::DeselectInvoiceCustomSectionService).to receive(:call!).and_call_original
  end

  describe "#call" do
    context "when update is successful" do
      it "updates the invoice custom section" do
        result = service_result

        expect(result).to be_success
        expect(result.invoice_custom_section.name).to eq("Updated Name")
        expect(BillingEntities::SelectInvoiceCustomSectionService).to have_received(:call!)
          .with(section: invoice_custom_section, billing_entity: default_billing_entity)
      end

      context "when pass selected as false" do
        let(:selected) { false }

        it "calls Deselect::ForOrganizationService when selected is false" do
          service_result
          expect(BillingEntities::DeselectInvoiceCustomSectionService).to have_received(:call!)
            .with(section: invoice_custom_section, billing_entity: default_billing_entity)
        end
      end
    end

    context "when update fails" do
      let(:update_params) { {name: nil} }

      it "handles validation errors" do
        expect(service_result).not_to be_success
        expect(service_result.error).to be_a(BaseService::ValidationFailure)
        expect(service_result.error.messages[:name]).to eq(["value_is_mandatory"])
      end
    end
  end
end
