# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::TaxSerializer do
  subject(:payload) { described_class.new(tax).serialize }

  let(:tax) { create(:tax, :applied_to_billing_entity, applied_to_organization: true) }

  it "serializes only tax attributes, with a null deletion timestamp" do
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

  context "when the tax is deleted" do
    let(:tax) { create(:tax, deleted_at: Time.current) }

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
