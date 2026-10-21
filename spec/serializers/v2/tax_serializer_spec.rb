# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::TaxSerializer do
  subject(:payload) { described_class.new(tax, includes:).serialize }

  let(:tax) { create(:tax, :applied_to_billing_entity, applied_to_organization: true) }
  let(:includes) { [] }

  it "serializes only tax attributes" do
    expect(payload).to eq(
      lago_id: tax.id,
      name: tax.name,
      code: tax.code,
      rate: tax.rate,
      description: tax.description,
      created_at: tax.created_at.iso8601,
      updated_at: tax.updated_at.iso8601
    )
  end

  context "when the tax is deleted" do
    let(:tax) { create(:tax, deleted_at: Time.current) }

    it "does not expose the deletion timestamp by default" do
      expect(payload).not_to have_key(:deleted_at)
    end

    context "with the internal deleted_at option" do
      let(:includes) { [:deleted_at] }

      it "includes the deletion timestamp" do
        expect(payload).to eq(
          lago_id: tax.id,
          name: tax.name,
          code: tax.code,
          rate: tax.rate,
          description: tax.description,
          created_at: tax.created_at.iso8601,
          updated_at: tax.updated_at.iso8601,
          deleted_at: tax.deleted_at.iso8601
        )
      end
    end
  end

  context "with the internal deleted_at option" do
    let(:includes) { [:deleted_at] }

    it "includes a null deletion timestamp for a kept tax" do
      expect(payload).to eq(
        lago_id: tax.id,
        name: tax.name,
        code: tax.code,
        rate: tax.rate,
        description: tax.description,
        created_at: tax.created_at.iso8601,
        updated_at: tax.updated_at.iso8601,
        deleted_at: nil
      )
    end
  end
end
