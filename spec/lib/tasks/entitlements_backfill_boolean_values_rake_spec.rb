# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "entitlements:backfill_boolean_values" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["entitlements:backfill_boolean_values"] }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:entitlement) { create(:entitlement, organization:, feature:) }
  let(:enabled) { create(:privilege, organization:, feature:, code: "enabled", value_type: "boolean") }
  let(:beta) { create(:privilege, organization:, feature:, code: "beta", value_type: "boolean") }
  let(:label) { create(:privilege, organization:, feature:, code: "label", value_type: "string") }
  let(:enabled_value) { create(:entitlement_value, organization:, entitlement:, privilege: enabled, value: "t") }
  let(:beta_value) { create(:entitlement_value, organization:, entitlement:, privilege: beta, value: "f", deleted_at: 1.day.ago) }
  let(:label_value) { create(:entitlement_value, organization:, entitlement:, privilege: label, value: "t") }

  let(:other_organization) { create(:organization) }
  let(:other_feature) { create(:feature, organization: other_organization) }
  let(:other_privilege) { create(:privilege, organization: other_organization, feature: other_feature, value_type: "boolean") }
  let(:other_value) do
    create(
      :entitlement_value,
      organization: other_organization,
      entitlement: create(:entitlement, organization: other_organization, feature: other_feature),
      privilege: other_privilege,
      value: "t"
    )
  end

  def stored_value(entitlement_value)
    Entitlement::EntitlementValue.with_discarded.find(entitlement_value.id).value
  end

  before do
    Rake.application.rake_require("tasks/entitlements")
    Rake::Task.define_task(:environment)
    task.reenable

    enabled_value
    beta_value
    label_value
    other_value
  end

  context "when DRY_RUN is disabled" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    it "rewrites the boolean values stored as t and f, deleted ones included" do
      expect { task.invoke }.to output(/Done. 3 values were rewritten/).to_stdout

      expect(stored_value(enabled_value)).to eq("true")
      expect(stored_value(beta_value)).to eq("false")
      expect(stored_value(other_value)).to eq("true")
    end

    it "leaves the values of other privileges" do
      expect { task.invoke }.to output.to_stdout

      expect(stored_value(label_value)).to eq("t")
    end

    context "with an organization_id argument" do
      it "rewrites only that organization's values" do
        expect { task.invoke(organization.id) }.to output(/Done. 2 values were rewritten/).to_stdout

        expect(stored_value(enabled_value)).to eq("true")
        expect(stored_value(other_value)).to eq("t")
      end
    end
  end

  context "when DRY_RUN is not set" do
    it "lists the values without changing them" do
      expect { task.invoke }
        .to output(/\[DRY RUN\] entitlement_value=#{enabled_value.id} organization=#{organization.id} t -> true/).to_stdout

      expect(stored_value(enabled_value)).to eq("t")
      expect(stored_value(beta_value)).to eq("f")
    end
  end
end
