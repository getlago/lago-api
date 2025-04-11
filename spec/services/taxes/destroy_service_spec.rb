# frozen_string_literal: true

require "rails_helper"

RSpec.describe Taxes::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(tax:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:tax) { create(:tax, organization:) }
  let(:tax2) { create(:tax, organization:) }
  let(:applied_tax2) { create(:billing_entity_applied_tax, billing_entity:, tax: tax2) }
  let(:customer) { create(:customer, organization:) }

  describe "#call" do
    before { tax }

    it "destroys the tax" do
      expect { destroy_service.call }.to change(Tax, :count).by(-1)
    end

    it "marks invoices as ready to be refreshed" do
      draft_invoice = create(:invoice, :draft, organization:, customer:)

      expect { destroy_service.call }.to change { draft_invoice.reload.ready_to_be_refreshed }.to(true)
    end

    it "does not remove the tax from the default billing entity" do
      expect { destroy_service.call }.not_to change { billing_entity.applied_taxes.count }
    end

    context "when tax is applied to the default billing entity" do
      before { create(:billing_entity_applied_tax, billing_entity:, tax:) }

      it "removes the tax from the default billing entity" do
        expect { destroy_service.call }.to change { billing_entity.applied_taxes.count }.by(-1)
      end
    end

    context "when tax is not found" do
      let(:tax) { nil }

      it "returns an error" do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq("tax_not_found")
        end
      end
    end
  end
end
