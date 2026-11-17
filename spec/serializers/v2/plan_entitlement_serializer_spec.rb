# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::PlanEntitlementSerializer do
  subject(:payload) { described_class.new(entitlement, **options).serialize }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:, code: "premium") }
  let_it_be(:feature) { create(:feature, organization:, code: "seats") }
  let_it_be(:integer_privilege) do
    create(:privilege, :integer_type, organization:, feature:, code: "max", created_at: Time.zone.parse("2026-01-01T10:00:00Z"))
  end
  let_it_be(:boolean_privilege) do
    create(:privilege, :boolean_type, organization:, feature:, code: "enabled", created_at: Time.zone.parse("2026-01-01T10:01:00Z"))
  end
  let_it_be(:string_privilege) do
    create(:privilege, :string_type, organization:, feature:, code: "tier", created_at: Time.zone.parse("2026-01-01T10:02:00Z"))
  end

  let(:options) { {} }
  let(:entitlement) do
    create(
      :entitlement,
      :catalog_plan,
      organization:,
      catalog_plan:,
      feature:,
      created_at: Time.zone.parse("2026-01-05T10:00:00.123456Z"),
      updated_at: Time.zone.parse("2026-01-06T11:30:00.654321Z")
    )
  end
  let(:flat_payload) do
    {
      lago_id: entitlement.id,
      plan_code: "premium",
      feature_code: "seats",
      values: [],
      created_at: "2026-01-05T10:00:00Z",
      updated_at: "2026-01-06T11:30:00Z",
      deleted_at: nil
    }
  end

  it "serializes the entitlement, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
  end

  context "with values" do
    before do
      travel_to(entitlement.updated_at) do
        # Written in another order than their privileges, to check that the order comes from the privileges
        create(:entitlement_value, organization:, entitlement:, privilege: boolean_privilege, value: "true",
          created_at: Time.zone.parse("2026-01-05T10:00:00Z"))
        create(:entitlement_value, organization:, entitlement:, privilege: integer_privilege, value: "50",
          created_at: Time.zone.parse("2026-01-05T10:01:00Z"))
        create(:entitlement_value, organization:, entitlement:, privilege: string_privilege, value: "gold",
          created_at: Time.zone.parse("2026-01-05T10:02:00Z"))
      end
    end

    it "renders the values newest privilege first, cast by privilege type" do
      expect(payload).to eq(
        flat_payload.merge(
          values: [
            {privilege_code: "tier", value: "gold"},
            {privilege_code: "enabled", value: true},
            {privilege_code: "max", value: 50}
          ]
        )
      )
    end
  end

  context "with privileges created at the same time" do
    let(:created_at) { Time.zone.parse("2026-01-02T10:00:00Z") }
    let(:first_privilege) do
      create(:privilege, :string_type, id: "00000000-0000-0000-0000-000000000001", organization:, feature:, code: "region", created_at:)
    end
    let(:second_privilege) do
      create(:privilege, :string_type, id: "00000000-0000-0000-0000-000000000002", organization:, feature:, code: "zone", created_at:)
    end

    before do
      travel_to(entitlement.updated_at) do
        # Written in the reverse order of their privilege ids
        create(:entitlement_value, organization:, entitlement:, privilege: second_privilege, value: "west")
        create(:entitlement_value, organization:, entitlement:, privilege: first_privilege, value: "eu")
      end
    end

    it "orders them by privilege id" do
      expect(payload).to eq(
        flat_payload.merge(
          values: [
            {privilege_code: "region", value: "eu"},
            {privilege_code: "zone", value: "west"}
          ]
        )
      )
    end
  end

  context "with a discarded value" do
    before do
      travel_to(entitlement.updated_at) do
        create(:entitlement_value, organization:, entitlement:, privilege: integer_privilege, value: "50")
        create(:entitlement_value, organization:, entitlement:, privilege: string_privilege, value: "gold", deleted_at: Time.current)
      end
    end

    it "does not render it" do
      expect(payload).to eq(flat_payload.merge(values: [{privilege_code: "max", value: 50}]))
    end
  end

  context "with a value whose privilege is discarded" do
    let(:discarded_privilege) { create(:privilege, :string_type, organization:, feature:, code: "legacy") }

    before do
      travel_to(entitlement.updated_at) do
        create(:entitlement_value, organization:, entitlement:, privilege: integer_privilege, value: "50")
        create(:entitlement_value, organization:, entitlement:, privilege: discarded_privilege, value: "old")
      end
      discarded_privilege.discard!
    end

    it "skips the value" do
      expect(payload).to eq(flat_payload.merge(values: [{privilege_code: "max", value: 50}]))
    end
  end

  context "when the entitlement belongs to a legacy plan" do
    let(:entitlement) do
      create(
        :entitlement,
        organization:,
        plan: create(:plan, organization:),
        feature:,
        created_at: Time.zone.parse("2026-01-05T10:00:00Z"),
        updated_at: Time.zone.parse("2026-01-06T11:30:00Z")
      )
    end

    it "renders a null plan code" do
      expect(payload).to eq(flat_payload.merge(plan_code: nil))
    end
  end

  context "with the usec_timestamps include" do
    let(:options) { {includes: %i[usec_timestamps]} }

    it "renders the timestamps to the microsecond" do
      expect(payload).to eq(
        flat_payload.merge(
          created_at: "2026-01-05T10:00:00.123456Z",
          updated_at: "2026-01-06T11:30:00.654321Z"
        )
      )
    end
  end
end
