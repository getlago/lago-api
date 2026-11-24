# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::TaxItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:tax) { create(:tax, organization: sandbox, code: "vat") }

  it "answers its item type and no activity type" do
    expect(item.item_type).to eq("tax")
    expect(item.activity_type).to be_nil
  end

  describe "#find_existing" do
    let(:live_tax) { create(:tax, organization: production, code: "vat") }

    before { live_tax }

    it "finds the kept production tax with the same code" do
      expect(item.find_existing(tax)).to eq(live_tax)
    end

    context "when the production tax is deleted" do
      before { live_tax.discard! }

      it "finds nothing" do
        expect(item.find_existing(tax)).to be_nil
      end
    end
  end

  describe "#copy!" do
    let(:tax) { create(:tax, :applied_to_billing_entity, organization: sandbox, code: "vat", name: "VAT", rate: 20) }

    it "creates the tax in production without applying it to the billing entity" do
      copy = item.copy!(tax, {})

      expect(copy).to have_attributes(organization: production, code: "vat", name: "VAT", rate: 20)
      expect(production.default_billing_entity.taxes).to be_empty
    end

    context "when production has a deleted tax with the same code" do
      before { create(:tax, organization: production, code: "vat").discard! }

      it "creates the tax" do
        expect(item.copy!(tax, {})).to have_attributes(organization: production, code: "vat", deleted_at: nil)
      end
    end
  end
end
