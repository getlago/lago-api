# frozen_string_literal: true

return unless License.premium?
return if ENV["LAGO_CLICKHOUSE_ENABLED"].blank?

topic = Utils::SecurityLog.topic
return if topic.blank?

existing = Karafka::Admin.cluster_info.topics.map { |t| t[:topic_name] }
unless existing.include?(topic)
  Karafka::Admin.create_topic(topic, 1, 1)
end
