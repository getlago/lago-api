# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::SelectInvoiceCustomSectionService, type: :service do
  describe "#call" do
    subject(:result) { described_class.call(section:, billing_entity:) }

    let(:organization) { create(:organization) }
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:section) { create(:invoice_custom_section, organization:) }

    it "selects the section for the organization" do
      expect { result }.to change(billing_entity.selected_invoice_custom_sections, :count).by(1)
      expect(result.section).to eq(section)
      expect(result.billing_entity).to eq(billing_entity)
      expect(billing_entity.selected_invoice_custom_sections).to include(section)
    end
  end
end
