# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_rate_cards_taxes view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:tax) { create(:tax, organization:) }
  let!(:applied_tax) { create(:rate_card_applied_tax, rate_card:, tax:, organization:) }

  it "exposes the applied tax with its parent and tax ids" do
    row = ActiveRecord::Base.connection.select_one("SELECT * FROM exports_rate_cards_taxes").symbolize_keys

    expect(row).to eq(
      organization_id: organization.id,
      lago_id: applied_tax.id,
      lago_rate_card_id: rate_card.id,
      lago_tax_id: tax.id,
      created_at: applied_tax.reload.created_at,
      updated_at: applied_tax.updated_at
    )
  end
end
