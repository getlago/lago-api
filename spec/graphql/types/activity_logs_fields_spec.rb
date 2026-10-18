# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Activity logs fields" do # rubocop:disable RSpec/DescribeClass
  # The root activityLogs query requires audit_logs:view, so the field nested in resource types must too.
  LagoApiSchema.types.each_value do |type|
    next unless type.kind.object?
    next if type == Types::QueryType

    field = type.fields["activityLogs"]
    next unless field

    it "requires audit_logs:view on #{type.graphql_name}.activityLogs" do
      expect(field.permissions).to eq(["audit_logs:view"])
    end
  end
end
