# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::SelectInvoiceCustomSectionService, type: :service do
  describe "#call" do
    subject(:service_result) { described_class.call(section:) }

    let(:organization) { create(:organization) }
    let(:section) { create(:invoice_custom_section, organization:) }

    it "selects the section for the organization" do
      expect { service_result }.to change(organization.selected_invoice_custom_sections, :count).by(1)
      expect(organization.selected_invoice_custom_sections).to include(section)
    end
  end
end
