# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntitiesQuery do
  subject(:result) { described_class.call(organization:, pagination:) }

  let_it_be(:organization) { create_default(:organization) }
  let(:pagination) { CursorPagination::Cursor.new(table: "billing_entities", limit: 1) }
  let(:billing_entity) { create(:billing_entity, organization:, created_at: 1.day.from_now) }

  before do
    billing_entity
    create(:billing_entity, :archived, organization:)
    create(:billing_entity, :deleted, organization:)
    create(:billing_entity, organization: create(:organization))
  end

  it "paginates active entities within the organization" do
    expect(result).to be_success
    page = CursorPagination::Page.new(records: result.billing_entities, cursor: pagination)
    expect(page.records).to eq([billing_entity])
    expect(page.meta[:next_cursor]).to be_present
  end

  context "without pagination" do
    let(:pagination) { nil }

    it "excludes foreign, archived and deleted entities" do
      expect(result.billing_entities).to eq([organization.default_billing_entity, billing_entity])
    end
  end
end
