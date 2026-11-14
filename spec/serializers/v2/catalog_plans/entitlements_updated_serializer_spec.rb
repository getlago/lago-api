# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::CatalogPlans::EntitlementsUpdatedSerializer do
  subject(:payload) { described_class.new(catalog_plan, root_name: "plan").for_webhook!.serialize }

  let(:organization) { create(:organization) }
  let(:catalog_plan) do
    create(
      :catalog_plan,
      organization:,
      name: "Premium",
      invoice_display_name: "Premium plan",
      code: "premium",
      description: "Premium monthly plan",
      currency: "USD",
      created_at: Time.zone.parse("2026-09-01T08:30:00Z")
    )
  end
  let(:tax) { create(:tax, organization:, name: "VAT", code: "vat", rate: 20.0, description: "French VAT") }
  let(:seats) { create(:feature, organization:, code: "seats") }
  let(:sso) { create(:feature, organization:, code: "sso") }
  let(:max) { create(:privilege, :integer_type, organization:, feature: seats, code: "max") }
  let(:tier) { create(:privilege, :string_type, organization:, feature: seats, code: "tier") }
  let(:enabled) { create(:privilege, :boolean_type, organization:, feature: sso, code: "enabled") }
  # Created before the seats one, to check the oldest first order
  let(:sso_entitlement) do
    create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: sso,
      created_at: Time.zone.parse("2026-09-02T10:00:00.123456Z"), updated_at: Time.zone.parse("2026-09-03T10:00:00Z"))
  end
  let(:seats_entitlement) do
    create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: seats,
      created_at: Time.zone.parse("2026-09-04T10:00:00Z"), updated_at: Time.zone.parse("2026-09-05T10:00:00Z"))
  end

  before do
    create(:plan_rate_card, organization:, catalog_plan:)
    create(:plan_applied_tax, :catalog_plan, organization:, catalog_plan:, tax:)
  end

  context "with entitlements" do
    before do
      seats_entitlement
      sso_entitlement
      # A value touches its entitlement: created at the entitlement's updated_at to keep it
      travel_to(seats_entitlement.updated_at) do
        create(:entitlement_value, organization:, entitlement: seats_entitlement, privilege: max, value: "50",
          created_at: Time.zone.parse("2026-09-04T10:00:00Z"))
        create(:entitlement_value, organization:, entitlement: seats_entitlement, privilege: tier, value: "gold",
          created_at: Time.zone.parse("2026-09-04T10:01:00Z"))
        create(:entitlement_value, organization:, entitlement: seats_entitlement, privilege: tier, value: "silver",
          deleted_at: Time.current)
      end
      travel_to(sso_entitlement.updated_at) do
        create(:entitlement_value, organization:, entitlement: sso_entitlement, privilege: enabled, value: "true")
      end
      create(:entitlement, :catalog_plan, organization:, catalog_plan:, deleted_at: Time.current)
      create(:entitlement, organization:, feature: seats)
    end

    it "renders the plan as its webhooks send it, with its kept entitlements oldest first" do
      expect(payload).to eq(
        lago_id: catalog_plan.id,
        name: "Premium",
        invoice_display_name: "Premium plan",
        code: "premium",
        description: "Premium monthly plan",
        currency: "USD",
        applied_rate_cards_count: 1,
        created_at: "2026-09-01T08:30:00Z",
        deleted_at: nil,
        taxes: [
          {
            lago_id: tax.id,
            name: "VAT",
            code: "vat",
            rate: 20.0,
            description: "French VAT",
            created_at: tax.created_at.iso8601,
            updated_at: tax.updated_at.iso8601,
            deleted_at: nil
          }
        ],
        entitlements: [
          {
            lago_id: sso_entitlement.id,
            plan_code: "premium",
            feature_code: "sso",
            values: [{privilege_code: "enabled", value: true}],
            created_at: "2026-09-02T10:00:00Z",
            updated_at: "2026-09-03T10:00:00Z",
            deleted_at: nil
          },
          {
            lago_id: seats_entitlement.id,
            plan_code: "premium",
            feature_code: "seats",
            values: [{privilege_code: "max", value: 50}, {privilege_code: "tier", value: "gold"}],
            created_at: "2026-09-04T10:00:00Z",
            updated_at: "2026-09-05T10:00:00Z",
            deleted_at: nil
          }
        ]
      )
    end

    it "renders the plan fields exactly as plan.updated does" do
      plan_updated = Webhooks::Plans::UpdatedService.new(object: catalog_plan).send(:object_serializer).for_webhook!.serialize

      expect(payload.except(:entitlements)).to eq(plan_updated)
    end

    context "with entitlements created at the same time" do
      let(:created_at) { Time.zone.parse("2026-09-04T10:00:00Z") }
      let(:sso_entitlement) do
        create(:entitlement, :catalog_plan, id: "00000000-0000-0000-0000-000000000002", organization:, catalog_plan:,
          feature: sso, created_at:)
      end
      let(:seats_entitlement) do
        create(:entitlement, :catalog_plan, id: "00000000-0000-0000-0000-000000000001", organization:, catalog_plan:,
          feature: seats, created_at:)
      end

      it "orders them by id" do
        expect(payload[:entitlements].pluck(:feature_code)).to eq(%w[seats sso])
      end
    end
  end

  context "without kept entitlements" do
    before { create(:entitlement, :catalog_plan, organization:, catalog_plan:, deleted_at: Time.current) }

    it "renders an empty list" do
      expect(payload[:entitlements]).to eq([])
    end
  end

  context "with many entitlements", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
    before do
      3.times do |index|
        feature = create(:feature, organization:)
        entitlement = create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:)
        create(:entitlement_value, organization:, entitlement:,
          privilege: create(:privilege, :integer_type, organization:, feature:, code: "max_#{index}"), value: "1")
        create(:entitlement_value, organization:, entitlement:,
          privilege: create(:privilege, :boolean_type, organization:, feature:, code: "on_#{index}"), value: "true")
      end
    end

    it "renders them without N+1 queries" do
      expect(payload[:entitlements].size).to eq(3)
    end
  end
end
