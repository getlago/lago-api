# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_billing_entities_taxes view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:tax) { create(:tax, organization:) }
  let!(:applied_tax) { create(:billing_entity_applied_tax, billing_entity:, tax:, organization:) }

  it "exposes the applied tax with its parent and tax ids" do
    row = ActiveRecord::Base.connection.select_one("SELECT * FROM exports_billing_entities_taxes").symbolize_keys

    expect(row).to eq(
      organization_id: organization.id,
      lago_id: applied_tax.id,
      lago_billing_entity_id: billing_entity.id,
      lago_tax_id: tax.id,
      created_at: applied_tax.reload.created_at,
      updated_at: applied_tax.updated_at
    )
  end
end
