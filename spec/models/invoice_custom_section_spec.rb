# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceCustomSection, type: :model do
  subject(:invoice_custom_section) { create(:invoice_custom_section) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:customer_applied_invoice_custom_sections).dependent(:destroy) }
  it { is_expected.to have_many(:billing_entity_applied_invoice_custom_sections).dependent(:destroy) }

  describe "enums" do
    it "defines section_type enum with correct values" do
      expect(described_class.section_types).to eq(
        "manual" => "manual",
        "system_generated" => "system_generated"
      )
    end

    it "has manual as the default section_type" do
      expect(invoice_custom_section.section_type).to eq("manual")
    end
  end

  describe "#selected_for_default_billing_entity?" do
    it { is_expected.not_to be_selected_for_default_billing_entity }

    context "when the section is selected for a billing entity" do
      let(:organization) { invoice_custom_section.organization }
      let(:billing_entity) { create(:billing_entity, organization:) }

      before do
        create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section:)
      end

      it { is_expected.not_to be_selected_for_default_billing_entity }
    end

    context "when the section is selected for the default billing entity" do
      let(:organization) { invoice_custom_section.organization }
      let(:billing_entity) { organization.default_billing_entity }

      before do
        create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section:)
      end

      it { is_expected.to be_selected_for_default_billing_entity }
    end
  end
end
