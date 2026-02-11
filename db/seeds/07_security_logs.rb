# frozen_string_literal: true

return unless ENV["LAGO_CLICKHOUSE_ENABLED"].present?

topic = Utils::SecurityLog.topic
return unless topic.present?

existing = Karafka::Admin.cluster_info.topics.map { |t| t[:topic_name] }
unless existing.include?(topic)
  Karafka::Admin.create_topic(topic, 1, 1)
end

organization = Organization.find_by!(name: "Hooli")
user = organization.memberships.first!.user

Utils::SecurityLog.produce(
  organization:,
  log_type: "role",
  log_event: "role.created",
  user:,
  resources: {role_code: "accountant", permissions: %w[customers:view invoices:view invoices:create]},
  skip_organization_check: true
)
