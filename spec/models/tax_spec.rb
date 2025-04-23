# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tax, type: :model do
  subject(:tax) { create(:tax, applied_to_organization:) }

  let(:applied_to_organization) { false }

  it { is_expected.to belong_to(:organization) }

  it { is_expected.to have_many(:billing_entities_taxes).dependent(:destroy) }
  it { is_expected.to have_many(:billing_entities).through(:billing_entities_taxes) }

  it_behaves_like "paper_trail traceable"

  describe "customers_count" do
    let(:customer) { create(:customer, organization: tax.organization) }

    before { create(:customer_applied_tax, customer:, tax:) }

    it "returns the number of attached customer" do
      expect(tax.customers_count).to eq(1)
    end

    context "when tax is applied to the billing_entity" do
      let(:applied_to_organization) { true }
      let(:applied_to_billing_entity_tax) { create(:billing_entity_applied_tax, tax:, billing_entity: tax.organization.default_billing_entity) }

      before do
        create(:customer, organization: tax.organization)
        applied_to_billing_entity_tax
      end

      it "returns the number of customer without tax" do
        expect(tax.customers_count).to eq(2)
      end
    end

    context "when tax is applied to multiple billing entities" do
      let(:organization) { tax.organization }
      let(:billing_entity) { organization.default_billing_entity }
      let(:billing_entity_2) { create(:billing_entity, organization:) }
      let(:billing_entity_3) { create(:billing_entity, organization:) }
      let(:applied_to_billing_entity_tax) { create(:billing_entity_applied_tax, tax:, billing_entity:) }
      let(:applied_to_billing_entity_tax_2) { create(:billing_entity_applied_tax, tax:, billing_entity: billing_entity_2) }
      let(:customer) { create(:customer, organization:) }
      let(:customer_2) { create(:customer, organization:, billing_entity: billing_entity_2) }
      let(:customer_3) { create(:customer, organization:, billing_entity: billing_entity_3) }
      let(:customer_4) { create(:customer, organization:, billing_entity: billing_entity_3) }
      let(:customer_4_applied_tax) { create(:customer_applied_tax, customer: customer_4, tax:) }

      before do
        applied_to_billing_entity_tax
        applied_to_billing_entity_tax_2
        customer_4_applied_tax
        customer
        customer_2
        customer_3
      end

      it "returns correct number of customers" do
        expect(tax.customers_count).to eq(3)
      end
    end
  end
end
