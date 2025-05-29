# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceCustomSections::CreateService, type: :service do
  describe "#call" do
    subject(:service_result) { described_class.call(organization:, create_params:, selected:) }

    let(:organization) { create(:organization) }
    let(:default_billing_entity) { organization.default_billing_entity }
    let(:create_params) { nil }
    let(:selected) { nil }

    context "with valid params" do
      let(:create_params) do
        {
          code: "test",
          details: "This text will be displayed in the invoice",
          display_name: "This will be the section title",
          name: "my firsts section"
        }
      end

      before do
        allow(BillingEntities::SelectInvoiceCustomSectionService).to receive(:call!).and_call_original
      end

      context "when selected is true" do
        let(:selected) { true }

        it "creates an invoice_custom_section that belongs to the organization" do
          expect { service_result }.to change(organization.invoice_custom_sections, :count).by(1)
          expect(service_result.invoice_custom_section).to be_persisted.and have_attributes(create_params)
        end

        it "applies the invoice custom section to the default billing entity" do
          invoice_custom_section = service_result.invoice_custom_section
          expect(default_billing_entity.selected_invoice_custom_sections).to include(invoice_custom_section)
          expect(BillingEntities::SelectInvoiceCustomSectionService).to have_received(:call!)
            .with(section: service_result.invoice_custom_section, billing_entity: default_billing_entity)
            .once
        end
      end

      context "when selected is false" do
        let(:selected) { false }

        it "creates an invoice_custom_section that belongs to the organization" do
          expect { service_result }.to change(organization.invoice_custom_sections, :count).by(1)
          expect(service_result.invoice_custom_section).to be_persisted.and have_attributes(create_params)
        end

        it "does not apply the invoice custom section to the default billing entity" do
          invoice_custom_section = service_result.invoice_custom_section
          expect(default_billing_entity.selected_invoice_custom_sections).not_to include(invoice_custom_section)
          expect(BillingEntities::SelectInvoiceCustomSectionService).not_to have_received(:call!)
            .with(section: invoice_custom_section, billing_entity: default_billing_entity)
        end
      end
    end

    context "with invalid params" do
      let(:params) { {} }

      it "returns an error" do
        expect(service_result).not_to be_success
        expect(service_result.error).to be_a(BaseService::ValidationFailure)
        expect(service_result.error.messages[:code]).to eq(["value_is_mandatory"])
      end
    end
  end
end
