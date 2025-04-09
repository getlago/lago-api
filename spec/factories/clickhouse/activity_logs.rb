# frozen_string_literal: true

FactoryBot.define do
  factory :clickhouse_activity_log, class: "Clickhouse::ActivityLog" do
    transient do
      membership { create(:membership) }
    end

    organization_id { membership.organization_id }
    user_id { membership.user_id }
    activity_type { "create" }
    activity_source { "api" }
    logged_at { Time.current }
    object { { "foo" => "bar", "baz" => "qux" } }
    object_changes { { "foo" => "bar" } }
  end
end
