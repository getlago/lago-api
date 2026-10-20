# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Activity logs fields" do # rubocop:disable RSpec/DescribeClass
  # The root activityLogs query requires audit_logs:view, so the field nested in resource types must too.
  fields = LagoApiSchema.types.values
    .select { it.kind.object? && it != Types::QueryType && it.fields.key?("activityLogs") }
    .to_h { [it.graphql_name, it.fields["activityLogs"]] }

  it "finds the activityLogs fields" do
    expect(fields.size).to be >= 11
  end

  fields.each do |type_name, field|
    it "requires audit_logs:view on #{type_name}.activityLogs" do
      expect(field.permissions).to eq(["audit_logs:view"])
    end
  end
end
