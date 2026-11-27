# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::BillableMetricItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }

  it_behaves_like "a copy to production item matched by code", :billable_metric

  # A custom aggregation is refused by the create service; `properties` is read nowhere.
  it_behaves_like "a copy to production item copying every column", BillableMetric,
    left_out: %w[custom_aggregator properties]

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("billable_metric")
    expect(item.activity_type).to eq("billable_metric.copied_to_production")
  end
end
