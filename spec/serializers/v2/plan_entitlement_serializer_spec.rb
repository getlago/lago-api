# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::PlanEntitlementSerializer do
  subject(:payload) { described_class.new(entitlement, **options).serialize }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:, code: "premium") }
  let_it_be(:feature) { create(:feature, organization:, code: "seats") }
  let_it_be(:integer_privilege) { create(:privilege, :integer_type, organization:, feature:, code: "max") }
  let_it_be(:boolean_privilege) { create(:privilege, :boolean_type, organization:, feature:, code: "enabled") }
  let_it_be(:string_privilege) { create(:privilege, :string_type, organization:, feature:, code: "tier") }

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
      # A value touches its entitlement: created at the entitlement's updated_at to keep it
      travel_to(entitlement.updated_at) do
        # Created in another order than their timestamps, to check the oldest first order
        create(:entitlement_value, organization:, entitlement:, privilege: string_privilege, value: "gold",
          created_at: Time.zone.parse("2026-01-05T10:02:00Z"))
        create(:entitlement_value, organization:, entitlement:, privilege: integer_privilege, value: "50",
          created_at: Time.zone.parse("2026-01-05T10:00:00Z"))
        create(:entitlement_value, organization:, entitlement:, privilege: boolean_privilege, value: "true",
          created_at: Time.zone.parse("2026-01-05T10:01:00Z"))
      end
    end

    it "renders the values oldest first, cast by privilege type" do
      expect(payload).to eq(
        flat_payload.merge(
          values: [
            {privilege_code: "max", value: 50},
            {privilege_code: "enabled", value: true},
            {privilege_code: "tier", value: "gold"}
          ]
        )
      )
    end
  end

  context "when a value changes after the entitlement" do
    let(:entitlement_value) do
      travel_to(entitlement.updated_at) do
        create(:entitlement_value, organization:, entitlement:, privilege: integer_privilege, value: "50")
      end
    end

    before do
      entitlement_value
      travel_to(Time.zone.parse("2026-01-07T09:00:00Z")) { entitlement_value.update!(value: "60") }
      entitlement.reload
    end

    it "renders the time of the value change as updated_at" do
      expect(payload).to eq(
        flat_payload.merge(
          values: [{privilege_code: "max", value: 60}],
          updated_at: "2026-01-07T09:00:00Z"
        )
      )
    end
  end

  context "with values created at the same time" do
    let(:created_at) { Time.zone.parse("2026-01-05T10:00:00Z") }
    let(:value_ids) { %w[00000000-0000-0000-0000-000000000002 00000000-0000-0000-0000-000000000001] }

    before do
      travel_to(entitlement.updated_at) do
        create(:entitlement_value, id: value_ids.first, organization:, entitlement:, privilege: integer_privilege, value: "50", created_at:)
        create(:entitlement_value, id: value_ids.last, organization:, entitlement:, privilege: string_privilege, value: "gold", created_at:)
      end
    end

    it "orders them by id" do
      expect(payload).to eq(
        flat_payload.merge(
          values: [
            {privilege_code: "tier", value: "gold"},
            {privilege_code: "max", value: 50}
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
