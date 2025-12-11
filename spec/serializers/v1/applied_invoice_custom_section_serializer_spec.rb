# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::AppliedInvoiceCustomSectionSerializer do
  subject(:serializer) { described_class.new(applied_invoice_custom_section) }

  let(:subscription) { create(:subscription) }
  let(:applied_invoice_custom_section) do
    create(:subscription_applied_invoice_custom_section, subscription:)
  end

  describe "#serialize" do
    it "serializes the applied invoice custom section correctly" do
      serialized_data = serializer.serialize

      expect(serialized_data).to include(
        lago_id: applied_invoice_custom_section.id,
        invoice_custom_section_id: applied_invoice_custom_section.invoice_custom_section_id,
        created_at: applied_invoice_custom_section.created_at.iso8601
      )
    end
  end
end
