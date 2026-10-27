# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::OrganizationSerializer do
  subject(:payload) { described_class.new(organization, includes:).serialize }

  let(:organization) { build_stubbed(:organization) }
  let(:includes) { [] }

  it "serializes organization fields without billing settings or relationships" do
    expect(payload).to eq(
      lago_id: organization.id,
      name: organization.name,
      slug: organization.slug,
      email: organization.email,
      events_store: organization.events_store,
      created_at: organization.created_at.iso8601,
      updated_at: organization.updated_at.iso8601
    )
  end

  context "with the timestamp precision of a v2 response" do
    let(:includes) { %i[usec_timestamps] }

    it "renders timestamps to the microsecond" do
      expect(payload).to eq(
        lago_id: organization.id,
        name: organization.name,
        slug: organization.slug,
        email: organization.email,
        events_store: organization.events_store,
        created_at: organization.created_at.iso8601(6),
        updated_at: organization.updated_at.iso8601(6)
      )
    end
  end
end
