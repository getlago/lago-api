# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_record_deletions view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let!(:record_deletion) { create(:record_deletion, organization:, record_table: "fees") }

  it "exposes the tombstone with the identifiers a consumer needs to join on" do
    row = ActiveRecord::Base.connection.select_one("SELECT * FROM exports_record_deletions").symbolize_keys

    expect(row).to include(
      organization_id: organization.id,
      lago_id: record_deletion.id,
      table_name: "fees",
      lago_record_id: record_deletion.record_id
    )
  end
end
