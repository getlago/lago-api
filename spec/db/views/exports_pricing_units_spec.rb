# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_pricing_units view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let!(:pricing_unit) { create(:pricing_unit, organization:, description: "Credits used by AI features") }

  it "exports the pricing unit" do
    row = ActiveRecord::Base.connection.select_one("SELECT * FROM exports_pricing_units").symbolize_keys
    pricing_unit.reload

    expect(row).to eq(
      organization_id: organization.id,
      lago_id: pricing_unit.id,
      code: pricing_unit.code,
      name: pricing_unit.name,
      short_name: pricing_unit.short_name,
      description: "Credits used by AI features",
      created_at: pricing_unit.created_at,
      updated_at: pricing_unit.updated_at
    )
  end
end
