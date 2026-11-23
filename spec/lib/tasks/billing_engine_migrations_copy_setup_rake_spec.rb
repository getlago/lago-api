# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "billing_engine_migrations:copy_setup", :premium do # rubocop:disable RSpec/DescribeClass
  let_it_be(:organization) { create(:organization) }
  let_it_be(:tax) { create(:tax, organization:, code: "vat_fr") }
  let_it_be(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }

  let(:task) { Rake::Task["billing_engine_migrations:copy_setup"] }
  let(:status) { "shadowing" }
  let(:shadow_organization) do
    create(:organization, webhook_url: nil, premium_integrations: ["multi_entities_enterprise"])
  end
  let(:billing_entity_code) { organization.default_billing_entity.code }

  before do
    Rake.application.rake_require("tasks/billing_engine_migrations")
    Rake::Task.define_task(:environment)
    task.reenable

    create(:billing_engine_migration, organization:, shadow_organization:, status:)
  end

  context "without an organization_id argument" do
    it "aborts with a usage message" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Missing organization_id argument/).to_stderr
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

      expect(shadow_organization.taxes).to be_empty
    end
  end

  context "when DRY_RUN is enabled (default)" do
    it "lists the records it would create and writes nothing" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "[DRY RUN] tax vat_fr: would_create",
          "[DRY RUN] billing_entity #{billing_entity_code}: would_create",
          "[DRY RUN] billable_metric api_calls: would_create",
          "Done [DRY RUN]: 3 would_create"
        )
      ).to_stdout

      expect(shadow_organization.taxes).to be_empty
      expect(shadow_organization.billable_metrics).to be_empty
    end
  end

  context "when DRY_RUN is disabled" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    it "creates the records, then skips them on the next run" do
      expect { task.invoke(organization.id) }.to output(/Done \[LIVE\]: 3 created/).to_stdout

      expect(shadow_organization.taxes.pluck(:code)).to eq(["vat_fr"])
      expect(shadow_organization.billable_metrics.pluck(:code)).to eq(["api_calls"])

      task.reenable
      expect { task.invoke(organization.id) }.to output(/Done \[LIVE\]: 3 skipped/).to_stdout
    end

    context "when a record fails" do
      let(:shadow_organization) { create(:organization, webhook_url: nil) }

      it "lists the error and aborts after copying the other records" do
        expect { task.invoke(organization.id) }
          .to raise_error(SystemExit, /1 record\(s\) failed/)
          .and output(/billing_entity #{billing_entity_code}: failed \(feature_unavailable\)/).to_stdout

        expect(shadow_organization.billable_metrics.pluck(:code)).to eq(["api_calls"])
      end
    end
  end
end
