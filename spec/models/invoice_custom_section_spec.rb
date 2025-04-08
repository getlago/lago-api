# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceCustomSection, type: :model do
  subject(:invoice_custom_section) { create(:invoice_custom_section) }

  it { is_expected.to belong_to(:organization) }

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
end
