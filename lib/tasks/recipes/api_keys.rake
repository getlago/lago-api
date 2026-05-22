# frozen_string_literal: true

require_relative "../../task_prompt"

# rubocop:disable Rails/Output,Rails/Exit
namespace :recipes do
  namespace :api_keys do
    desc "Expire all active API keys for an organization (force-revoke, bypasses last-key guard)"
    task expire_all: :environment do
      organization = TaskPrompt.ask_for_organization

      active_keys = organization.api_keys.active.to_a

      if active_keys.empty?
        puts "No active API keys found for #{organization.name}."
        next
      end

      puts ""
      puts "Found #{active_keys.size} active API key(s) for #{organization.name}:"
      active_keys.each do |key|
        puts "  - #{key.name} (••••#{key.value.last(4)})"
      end
      puts ""
      puts "This will force-expire ALL of them, bypassing the 'last non-expiring key' guard."
      puts "After this, the organization will have NO valid API keys."
      puts "If the organization is churning, also run `rake recipes:subscriptions:terminate_all`."
      TaskPrompt.confirm!("Continue? (y/n): ")

      active_keys.each_with_index do |key, index|
        prefix = "[#{index + 1}/#{active_keys.size}]"

        key.touch(:expires_at) # rubocop:disable Rails/SkipsModelValidations
        ApiKeys::CacheService.expire_cache(key.value)
        Utils::SecurityLog.produce(
          organization:,
          log_type: "api_key",
          log_event: "api_key.deleted",
          resources: {name: key.name, value_ending: key.value.last(4)}
        )

        puts "#{prefix} Expired #{key.name} (••••#{key.value.last(4)})"
      end

      puts ""
      puts "Done. #{active_keys.size} API key(s) expired."
    end
  end
end
# rubocop:enable Rails/Output,Rails/Exit
