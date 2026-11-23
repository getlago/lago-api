# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "billing_engine_migrations:copy_plan_entitlements" do # rubocop:disable RSpec/DescribeClass
  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:pro) { create(:plan, organization:, code: "pro") }
  let_it_be(:pro_catalog_plan) { create(:catalog_plan, organization: shadow_organization, code: "pro_v2") }
  let_it_be(:seats) { create(:feature, organization:, code: "seats") }
  let_it_be(:seats_max) { create(:privilege, feature: seats, code: "max", value_type: "integer") }

  let(:task) { Rake::Task["billing_engine_migrations:copy_plan_entitlements"] }
  let(:env) { {} }
  let(:status) { "shadowing" }
  let(:plan_mapping) { {"pro" => "pro_v2", "basic" => "basic_v2"} }
  let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:, status:, plan_mapping:) }

  before_all do
    create(:entitlement_value, entitlement: create(:entitlement, plan: pro, feature: seats), privilege: seats_max, value: "10")
  end

  before do
    Rake.application.rake_require("tasks/billing_engine_migrations")
    Rake::Task.define_task(:environment)
    task.reenable
    stub_const("ENV", ENV.to_h.merge(env))

    migration
  end

  context "without an organization_id argument" do
    it "aborts with a usage message" do
      expect { task.invoke }
        .to raise_error(SystemExit)
        .and output(/Usage: rake billing_engine_migrations:copy_plan_entitlements\[organization_id\]/).to_stderr
    end
  end

  context "when the organization has no migration" do
    it "aborts" do
      expect { task.invoke(create(:organization).id) }
        .to raise_error(SystemExit).and output(/No billing engine migration/).to_stderr
    end
  end

  context "when the migration is not shadowing" do
    let(:status) { "paused" }

    it "aborts without copying anything" do
      expect { task.invoke(organization.id) }.to raise_error(SystemExit).and output(/not shadowing/).to_stderr

      expect(shadow_organization.features).to be_empty
    end
  end

  context "when DRY_RUN is enabled (default)" do
    it "lists what it would copy and skip, and writes nothing" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "[DRY RUN] would create feature seats",
          "[DRY RUN] would create privilege seats.max",
          "[DRY RUN] would create entitlement seats on catalog plan pro_v2",
          "[DRY RUN] would create value seats.max on catalog plan pro_v2",
          "[DRY RUN] skipped plan basic (plan_not_found)",
          "[DRY RUN] skipped catalog plan basic_v2 (catalog_plan_not_found)",
          "Features: 1 created. Privileges: 1 created, 0 updated, 0 removed. Catalog plans: 1 synced. Mappings skipped: 1. " \
          "Entitlements: 1 created, 0 removed. Values: 1 created, 0 updated, 0 removed. [DRY RUN]"
        )
      ).to_stdout

      expect(shadow_organization.features).to be_empty
      expect(pro_catalog_plan.entitlements).to be_empty
    end
  end

  context "when DRY_RUN is disabled" do
    let(:env) { {"DRY_RUN" => "false"} }

    it "copies the features and the plan entitlements" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "[LIVE] created feature seats",
          "[LIVE] created entitlement seats on catalog plan pro_v2",
          "[LIVE] created value seats.max on catalog plan pro_v2"
        )
      ).to_stdout

      expect(shadow_organization.features.pluck(:code)).to eq(%w[seats])
      expect(pro_catalog_plan.entitlement_values.pluck(:value)).to eq(%w[10])
    end
  end

  context "when the catalog plan already has entitlements that differ from the plan" do
    let(:shadow_tier) do
      Entitlement::Privilege.find_by!(organization: shadow_organization, code: "tier")
    end

    before do
      create(:privilege, feature: seats, code: "tier", value_type: "select", config: {select_options: %w[silver gold]})

      shadow_seats = create(:feature, organization: shadow_organization, code: "seats")
      shadow_max = create(:privilege, feature: shadow_seats, code: "max", value_type: "integer")
      shadow_old = create(:privilege, feature: shadow_seats, code: "old", value_type: "string")
      create(:privilege, feature: shadow_seats, code: "tier", value_type: "select", config: {select_options: %w[silver]})
      shadow_seats_entitlement = create(:entitlement, :catalog_plan, catalog_plan: pro_catalog_plan, feature: shadow_seats)
      create(:entitlement_value, entitlement: shadow_seats_entitlement, privilege: shadow_max, value: "5")
      create(:entitlement_value, entitlement: shadow_seats_entitlement, privilege: shadow_old, value: "x")

      legacy = create(:feature, organization: shadow_organization, code: "legacy")
      create(:entitlement, :catalog_plan, catalog_plan: pro_catalog_plan, feature: legacy)
    end

    it "lists the updates and removals it would make, and rolls them back" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "[DRY RUN] would update privilege seats.tier",
          "[DRY RUN] would remove entitlement legacy on catalog plan pro_v2",
          "[DRY RUN] would update value seats.max on catalog plan pro_v2",
          "[DRY RUN] would remove value seats.old on catalog plan pro_v2",
          "Features: 0 created. Privileges: 0 created, 1 updated, 0 removed. Catalog plans: 1 synced. Mappings skipped: 1. " \
          "Entitlements: 0 created, 1 removed. Values: 0 created, 1 updated, 1 removed. [DRY RUN]"
        )
      ).to_stdout

      expect(shadow_tier.config).to eq({"select_options" => %w[silver]})
      expect(pro_catalog_plan.entitlements.count).to eq(2)
      expect(pro_catalog_plan.entitlement_values.pluck(:value)).to match_array(%w[5 x])
    end

    context "when DRY_RUN is disabled" do
      let(:env) { {"DRY_RUN" => "false"} }

      it "updates the privilege, then brings the catalog plan to the plan entitlements" do
        expect { task.invoke(organization.id) }.to output(
          a_string_including(
            "[LIVE] updated privilege seats.tier",
            "[LIVE] removed entitlement legacy on catalog plan pro_v2",
            "[LIVE] updated value seats.max on catalog plan pro_v2",
            "[LIVE] removed value seats.old on catalog plan pro_v2"
          )
        ).to_stdout

        expect(shadow_tier.config).to eq({"select_options" => %w[silver gold]})
        expect(pro_catalog_plan.entitlements.joins(:feature).pluck("entitlement_features.code")).to eq(%w[seats])
        expect(pro_catalog_plan.entitlement_values.pluck(:value)).to eq(%w[10])
      end
    end
  end

  context "when two plans with different entitlements are mapped to the same catalog plan" do
    let(:plan_mapping) { {"pro" => "pro_v2", "pro_legacy" => "pro_v2"} }

    before { create(:plan, organization:, code: "pro_legacy") }

    it "skips the catalog plan and counts each mapping" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "[DRY RUN] skipped catalog plan pro_v2 (mapped_plans_have_different_entitlements)",
          "Catalog plans: 0 synced. Mappings skipped: 2."
        )
      ).to_stdout
    end
  end

  context "when a shadow privilege has another value type" do
    let(:env) { {"DRY_RUN" => "false"} }

    before do
      shadow_seats = create(:feature, organization: shadow_organization, code: "seats")
      create(:privilege, feature: shadow_seats, code: "max", value_type: "string")
    end

    it "replaces it with the organization one" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "[LIVE] removed privilege seats.max",
          "[LIVE] created privilege seats.max",
          "Privileges: 1 created, 0 updated, 1 removed."
        )
      ).to_stdout
    end
  end
end
