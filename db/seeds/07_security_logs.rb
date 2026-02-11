# frozen_string_literal: true

return unless License.premium?
return if ENV["LAGO_CLICKHOUSE_ENABLED"].blank?

topic = Utils::SecurityLog.topic
return if topic.blank?

existing = Karafka::Admin.cluster_info.topics.map { |t| t[:topic_name] }
unless existing.include?(topic)
  Karafka::Admin.create_topic(topic, 1, 1)
end

organization = Organization.find_by!(name: "Hooli")
user = organization.memberships.first!.user

Utils::SecurityLog.produce(
  organization:,
  log_type: "user",
  log_event: "user.signed_up",
  user:,
  skip_organization_check: true
)

Utils::SecurityLog.produce(
  organization:,
  log_type: "user",
  log_event: "user.deleted",
  user:,
  resources: {email: "dinesh@hooli.com"}
)

Utils::SecurityLog.produce(
  organization:,
  log_type: "user",
  log_event: "user.invited",
  user:,
  resources: {invitee_email: "invited@example.com"}
)

Utils::SecurityLog.produce(
  organization:,
  log_type: "user",
  log_event: "user.role_edited",
  user:,
  resources: {email: "dinesh@hooli.com", roles: {deleted: %w[admin], added: %w[finance]}}
)
