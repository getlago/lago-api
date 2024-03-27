# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tax, type: :model do
  subject(:tax) { create(:tax, applied_to_organization:) }

  let(:applied_to_organization) { false }

  it_behaves_like "paper_trail traceable"

  describe "customers_count" do
    let(:customer) { create(:customer, organization: tax.organization) }

    before { create(:customer_applied_tax, customer:, tax:) }

    it "returns the number of attached customer" do
      expect(tax.customers_count).to eq(1)
    end

    context "when tax is applied by default" do
      let(:applied_to_organization) { true }

      before { create(:customer, organization: tax.organization) }

      it "returns the number of customer without tax" do
        expect(tax.customers_count).to eq(2)
      end
    end
  end
end
